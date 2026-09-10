import AVFoundation
import Foundation
import Observation
import Speech

/// Live microphone transcription.
///
/// Apple streams volatile (in-progress) results and then finalizes them, so the text
/// settles in place instead of the redraw-the-world flicker `whisper-stream` produces.
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
        let inputFormat = input.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            throw AudioSourceError.unreadable("No microphone input is available.")
        }

        // The mic rarely matches the analyzer's 16 kHz mono, so convert on the audio thread.
        let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
        let ratio = analyzerFormat.sampleRate / inputFormat.sampleRate

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converter else {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }

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

        engine.prepare()
        try engine.start()
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
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)

                if result.isFinal {
                    volatileText = ""
                    guard !text.isEmpty else { continue }
                    finalizedText += (finalizedText.isEmpty ? "" : " ") + text

                    var words: [TimedWord] = []
                    for run in result.text.runs {
                        guard let range = run.audioTimeRange else { continue }
                        let fragment = String(result.text[run.range].characters)
                        guard !fragment.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                        words.append(TimedWord(text: fragment,
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
