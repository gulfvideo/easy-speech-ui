import AVFoundation
import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case localeUnsupported(String)
    case noCompatibleFormat
    case noSpeechFound(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let id):
            "Apple's speech models don't support \(id) yet."
        case .noCompatibleFormat:
            "No compatible audio format was offered by the speech engine."
        case .noSpeechFound(let language):
            "No speech was found. The audio may be silent, or spoken in a language other than \(language)."
        case .cancelled:
            "Cancelled."
        }
    }
}

/// Transcribes a media file with `SpeechAnalyzer`.
///
/// Runs entirely on-device on the Neural Engine. Unlike `SFSpeechRecognizer`, there is
/// no one-minute ceiling and no network path, so a two-hour recording is a single pass.
struct FileTranscriber: Sendable {

    struct Options: Sendable {
        var locale: Locale
        var censorProfanity: Bool = false
        /// Names and terms to bias recognition toward.
        var vocabulary: [String] = []
        /// Applied to recognized text before it reaches the transcript.
        var corrections: [Correction] = []

        var transcriptionOptions: Set<SpeechTranscriber.TranscriptionOption> {
            censorProfanity ? [.etiquetteReplacements] : []
        }
    }

    /// Stages the UI can reflect while a single file is processed.
    enum Stage: Sendable {
        case preparing
        case downloadingModel(Progress)
        case transcribing(Double)
    }

    static func transcribe(
        url: URL,
        options: Options,
        stage: @escaping @Sendable (Stage) -> Void
    ) async throws -> Transcript {

        stage(.preparing)

        guard let locale = await LocaleCatalog.resolve(options.locale.normalizedIdentifier) else {
            throw TranscriptionError.localeUnsupported(options.locale.normalizedIdentifier)
        }

        // Finalized results only, with per-word time ranges so subtitles line up.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: options.transcriptionOptions,
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        try await LocaleCatalog.ensureInstalled(modules: [transcriber]) { progress in
            stage(.downloadingModel(progress))
        }
        await LocaleCatalog.reserve(locale)

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.noCompatibleFormat
        }

        // Fall back to FFmpeg only for containers AVFoundation won't open.
        var readURL = url
        var temporaryFile: URL?
        if AudioSource.needsFFmpeg(url) {
            let converted = try AudioSource.transcodeWithFFmpeg(url, sampleRate: format.sampleRate)
            readURL = converted
            temporaryFile = converted
        }
        defer {
            if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile) }
        }

        let duration = try await AudioSource.duration(of: readURL)

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Contextual strings bias the recognizer toward names it would otherwise guess
        // at. This is where accuracy errors concentrate, so it's the cheapest real win.
        if let context = AnalysisContextFactory.make(from: options.vocabulary) {
            try await analyzer.setContext(context)
        }

        // Warming the model before the first buffer avoids a stall on long files.
        try await analyzer.prepareToAnalyze(in: format)

        // Pull-based: the analyzer draws buffers as it consumes them, so memory stays
        // flat on long files. Progress is reported from finalized results, since decoding
        // races far ahead of recognition and is not what the user is waiting on.
        let stream = AudioSource.InputSequence(url: readURL, format: format)

        // Collect results concurrently with feeding audio, or the analyzer back-pressures.
        async let collected = collectSegments(from: transcriber,
                                              totalDuration: duration,
                                              stage: stage,
                                              corrections: options.corrections)

        do {
            _ = try await analyzer.analyzeSequence(stream)

            // On cancellation the input sequence stops early but `analyzeSequence` still
            // returns normally, and `finalizeAndFinishThroughEndOfInput` then waits
            // forever for an end of input that will never arrive. Tear the analyzer down
            // instead — this is what made Stop hang a job rather than end it.
            if Task.isCancelled {
                await analyzer.cancelAndFinishNow()
                _ = try? await collected
                throw CancellationError()
            }

            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            await analyzer.cancelAndFinishNow()
            _ = try? await collected
            throw error
        }

        let segments = try await collected

        // Succeeding with nothing is worse than failing: the user gets an empty file and
        // no idea why. Say which of the two likely causes it is.
        guard !segments.isEmpty else {
            throw TranscriptionError.noSpeechFound(LocaleCatalog.displayName(for: locale))
        }

        return Transcript(segments: segments,
                          localeIdentifier: locale.normalizedIdentifier)
    }

    /// Drains the transcriber's result stream into time-stamped segments, reporting
    /// progress from how far into the audio the recognizer has finalized.
    private static func collectSegments(
        from transcriber: SpeechTranscriber,
        totalDuration: TimeInterval,
        stage: @escaping @Sendable (Stage) -> Void,
        corrections: [Correction]
    ) async throws -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        /// Last whole percent reported, so progress is published at most 100 times per file.
        ///
        /// The analyzer finalizes a result per phrase — 2,757 of them for a two-hour podcast.
        /// Reporting every one meant 2,757 hops to the main actor, each spawning a Task and
        /// invalidating a row in a list that may hold hundreds of files. At one file at a time
        /// that was survivable; at six it saturated the main thread and made the whole app
        /// sluggish. A progress bar cannot show more than whole percents anyway.
        ///
        /// This loop is serial — one `for try await` over one sequence — so a plain local is
        /// all the synchronisation this needs.
        var lastReportedPercent = -1

        for try await result in transcriber.results {
            guard result.isFinal else { continue }

            if totalDuration > 0, result.range.end.isNumeric {
                let fraction = min(0.99, max(0, result.range.end.seconds / totalDuration))
                let percent = Int(fraction * 100)
                if percent != lastReportedPercent {
                    lastReportedPercent = percent
                    stage(.transcribing(fraction))
                }
            }

            let attributed = result.text
            let raw = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            let text = VocabularyCorrector.correct(SpokenNumbers.polish(raw), using: corrections)

            var words: [TimedWord] = []
            for run in attributed.runs {
                guard let range = run.audioTimeRange else { continue }
                let fragment = String(attributed[run.range].characters)
                guard !fragment.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                words.append(TimedWord(text: VocabularyCorrector.correct(
                                            SpokenNumbers.polish(fragment), using: corrections),
                                       start: range.start.seconds,
                                       end: range.end.seconds))
            }

            segments.append(TranscriptSegment(
                text: text,
                start: result.range.start.seconds,
                end: result.range.end.seconds,
                words: words
            ))
        }
        return segments
    }
}
