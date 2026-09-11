import AVFoundation
import CoreAudio
import Foundation
import Observation
import Speech

/// Live microphone transcription.
///
/// Apple streams volatile (in-progress) results and then finalizes them, so the tail of
/// the text can be revised in place while everything before it stays put. The UI shows
/// the volatile portion greyed so it's clear which part may still change.
@MainActor
@Observable
final class LiveTranscriber {

    private(set) var isRunning = false
    /// Text that has been finalized and won't change.
    private(set) var finalizedText = ""
    /// The in-flight tail the engine may still revise.
    private(set) var volatileText = ""
    private(set) var errorMessage: String?
    private(set) var segments: [TranscriptSegment] = []

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    var displayText: String {
        volatileText.isEmpty ? finalizedText
                             : finalizedText + (finalizedText.isEmpty ? "" : " ") + volatileText
    }

    var transcript: Transcript {
        Transcript(segments: segments, localeIdentifier: localeIdentifier)
    }

    private var localeIdentifier = ""

    // MARK: - Control

    func start(localeIdentifier requestedLocale: String) async {
        guard !isRunning else { return }
        errorMessage = nil
        finalizedText = ""
        volatileText = ""
        segments = []

        guard await requestMicrophoneAccess() else {
            errorMessage = "EasySpeech needs microphone access. Grant it in System Settings › Privacy & Security › Microphone."
            return
        }

        do {
            guard let locale = await LocaleCatalog.resolve(requestedLocale) else {
                throw TranscriptionError.localeUnsupported(requestedLocale)
            }
            localeIdentifier = locale.normalizedIdentifier

            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [.audioTimeRange]
            )
            try await LocaleCatalog.ensureInstalled(modules: [transcriber])

            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw TranscriptionError.noCompatibleFormat
            }

            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.continuation = continuation

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            if let context = AnalysisContextFactory.make(from: AppSettings.shared.vocabulary) {
                try await analyzer.setContext(context)
            }

            try await analyzer.prepareToAnalyze(in: analyzerFormat)

            resultsTask = Task { [weak self] in
                await self?.consume(transcriber)
            }

            try startEngine(analyzerFormat: analyzerFormat, continuation: continuation)
            try await analyzer.start(inputSequence: stream)
            isRunning = true

        } catch {
            errorMessage = error.localizedDescription
            await teardown()
        }
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        continuation?.finish()

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await teardown()

        // Fold whatever was still in flight into the finalized text.
        if !volatileText.isEmpty {
            finalizedText += (finalizedText.isEmpty ? "" : " ") + volatileText
            volatileText = ""
        }
    }

    private func teardown() async {
        resultsTask?.cancel()
        resultsTask = nil
        continuation = nil
        analyzer = nil
        engine = nil
    }

    // MARK: - Audio capture

    private func startEngine(analyzerFormat: AVAudioFormat,
                             continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        let engine = AVAudioEngine()
        self.engine = engine

        let input = engine.inputNode

        // Must be set before the format is read: the input node reports the format of
        // whichever device it's pointed at, and changing it afterwards invalidates the tap.
        if let chosen = AudioInputCatalog.device(uid: AppSettings.shared.inputDeviceUID) {
            selectInput(chosen, on: input)
        }

        let inputFormat = input.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioSourceError.unreadable(
                "\(activeInputName) isn't providing any audio. Pick a different microphone and try again."
            )
        }

        // The tap handler is built by a nonisolated function on purpose. A closure formed
        // inside this @MainActor type inherits main-actor isolation, and AVAudioEngine
        // calls the tap on a realtime audio thread — Swift then checks the executor,
        // finds the wrong queue, and traps. That is a hard crash the moment recording
        // starts, not a warning.
        input.installTap(onBus: 0,
                         bufferSize: 4096,
                         format: inputFormat,
                         block: Self.makeTapHandler(inputFormat: inputFormat,
                                                    analyzerFormat: analyzerFormat,
                                                    continuation: continuation))

        engine.prepare()
        try engine.start()
    }

    /// Points AVAudioEngine's input node at a specific device.
    private func selectInput(_ device: AudioInputDevice, on input: AVAudioInputNode) {
        guard let unit = input.audioUnit else { return }
        var deviceID = device.id
        AudioUnitSetProperty(unit,
                             kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global,
                             0,
                             &deviceID,
                             UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    /// Name of the device dictation will actually use, for messages and the picker.
    var activeInputName: String {
        let uid = AppSettings.shared.inputDeviceUID
        if let chosen = AudioInputCatalog.device(uid: uid) { return chosen.name }
        return AudioInputCatalog.systemDefault()?.name ?? "the default microphone"
    }

    /// Builds the realtime tap callback outside any actor.
    ///
    /// Everything it captures is either Sendable or boxed, and it touches no state
    /// belonging to `LiveTranscriber`, so it is safe to run on the audio thread.
    private nonisolated static func makeTapHandler(
        inputFormat: AVAudioFormat,
        analyzerFormat: AVAudioFormat,
        continuation: AsyncStream<AnalyzerInput>.Continuation
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        // The mic rarely matches the analyzer's 16 kHz mono, so convert on the audio thread.
        let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
        let ratio = analyzerFormat.sampleRate / inputFormat.sampleRate

        return { buffer, _ in
            guard let converter else {
                continuation.yield(AnalyzerInput(buffer: UncheckedBox(buffer).value))
                return
            }

            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat,
                                                frameCapacity: capacity) else { return }

            var error: NSError?
            let supplied = UncheckedFlag()
            // `convert` invokes this synchronously on this same thread, so handing the
            // buffer straight through is safe despite AVAudioPCMBuffer not being Sendable.
            let source = UncheckedBox(buffer)
            converter.convert(to: output, error: &error) { _, status in
                if supplied.value {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied.value = true
                status.pointee = .haveData
                return source.value
            }

            if error == nil, output.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: output))
            }
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }

    // MARK: - Results

    private func consume(_ transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                let text = VocabularyCorrector.correct(
                    SpokenNumbers.polish(
                        String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    ),
                    using: AppSettings.shared.corrections
                )

                if result.isFinal {
                    volatileText = ""
                    guard !text.isEmpty else { continue }
                    finalizedText += (finalizedText.isEmpty ? "" : " ") + text

                    var words: [TimedWord] = []
                    for run in result.text.runs {
                        guard let range = run.audioTimeRange else { continue }
                        let fragment = String(result.text[run.range].characters)
                        guard !fragment.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                        words.append(TimedWord(text: SpokenNumbers.polish(fragment),
                                               start: range.start.seconds,
                                               end: range.end.seconds))
                    }
                    segments.append(TranscriptSegment(text: text,
                                                      start: result.range.start.seconds,
                                                      end: result.range.end.seconds,
                                                      words: words))
                } else {
                    volatileText = text
                }
            }
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}
