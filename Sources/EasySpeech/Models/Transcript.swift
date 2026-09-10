import Foundation

/// A single word with its audio time range, as reported by SpeechTranscriber.
struct TimedWord: Sendable, Hashable, Codable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

/// One finalized chunk of recognized speech.
struct TranscriptSegment: Identifiable, Sendable, Hashable, Codable {
    var id = UUID()
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var words: [TimedWord] = []

    var duration: TimeInterval { max(0, end - start) }
}

/// The full result of transcribing one file.
struct Transcript: Sendable, Hashable, Codable {
    var segments: [TranscriptSegment] = []
    var localeIdentifier: String = ""
    /// Set when the transcript has been run through the Translation framework.
    var translatedText: String?

    var isEmpty: Bool { segments.isEmpty }

    /// Every word across all segments, in order. Used to build tight subtitle cues.
    var words: [TimedWord] { segments.flatMap(\.words) }

    var plainText: String {
        segments.map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Paragraph-per-segment rendering, which reads better than one long line.
    var paragraphText: String {
        segments.map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var totalDuration: TimeInterval { segments.last?.end ?? 0 }
}
