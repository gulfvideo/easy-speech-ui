import AVFoundation
import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case localeUnsupported(String)
    case noCompatibleFormat
    case cancelled

    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let id):
            "Apple's speech models don't support \(id) yet."
        case .noCompatibleFormat:
            "No compatible audio format was offered by the speech engine."
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
        // Warming the model before the first buffer avoids a stall on long files.
        try await analyzer.prepareToAnalyze(in: format)

        // Pull-based: the analyzer draws buffers as it consumes them, so memory stays
        // flat on long files. Progress is reported from finalized results, since decoding
        // races far ahead of recognition and is not what the user is waiting on.
        let stream = AudioSource.InputSequence(url: readURL, format: format)

        // Collect results concurrently with feeding audio, or the analyzer back-pressures.
        async let collected = collectSegments(from: transcriber,
                                              totalDuration: duration,
                                              stage: stage)

        do {
            _ = try await analyzer.analyzeSequence(stream)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            await analyzer.cancelAndFinishNow()
            _ = try? await collected
            throw error
        }

        let segments = try await collected

        return Transcript(segments: segments,
                          localeIdentifier: locale.normalizedIdentifier)
    }

    /// Drains the transcriber's result stream into time-stamped segments, reporting
    /// progress from how far into the audio the recognizer has finalized.
    private static func collectSegments(
        from transcriber: SpeechTranscriber,
        totalDuration: TimeInterval,
        stage: @escaping @Sendable (Stage) -> Void
    ) async throws -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []

        for try await result in transcriber.results {
            guard result.isFinal else { continue }

            if totalDuration > 0, result.range.end.isNumeric {
                stage(.transcribing(min(0.99, max(0, result.range.end.seconds / totalDuration))))
            }

            let attributed = result.text
            let raw = String(attributed.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            let text = SpokenNumbers.polish(raw)

            var words: [TimedWord] = []
            for run in attributed.runs {
                guard let range = run.audioTimeRange else { continue }
                let fragment = String(attributed[run.range].characters)
                guard !fragment.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                words.append(TimedWord(text: SpokenNumbers.polish(fragment),
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
