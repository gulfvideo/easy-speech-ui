import Foundation

/// Builds .srt / .vtt / .txt payloads from a Transcript.
///
/// Apple's SpeechTranscriber hands back a time range per finalized result, and a
/// time range per *word* when `.audioTimeRange` is requested. Segment ranges alone
/// make poor subtitles — they can run 20+ seconds. So when word timings are present
/// we re-chunk them into cues sized for reading.
enum SubtitleWriter {

    struct CueOptions: Sendable {
        /// Roughly two 42-character lines, the broadcast convention.
        var maxCharacters = 84
        var maxDuration: TimeInterval = 6.0
        /// A pause longer than this forces a cue break.
        var maxGap: TimeInterval = 0.6
        var maxLineLength = 42

        static let `default` = CueOptions()
    }

    struct Cue: Sendable {
        var index: Int
        var start: TimeInterval
        var end: TimeInterval
        var text: String
    }

    // MARK: - Cue construction

    static func cues(for transcript: Transcript, options: CueOptions = .default) -> [Cue] {
        let words = transcript.words
        guard !words.isEmpty else { return cuesFromSegments(transcript) }

        var cues: [Cue] = []
        var current: [TimedWord] = []

        func flush() {
            guard !current.isEmpty else { return }
            let text = current.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { current = []; return }
            cues.append(Cue(index: cues.count + 1,
                            start: current.first!.start,
                            end: current.last!.end,
                            text: wrap(text, limit: options.maxLineLength)))
            current = []
        }

        for word in words {
            if let last = current.last {
                let wouldBeLength = current.map(\.text).joined().count + word.text.count
                let wouldBeDuration = word.end - current[0].start
                let gap = word.start - last.end
                if wouldBeLength > options.maxCharacters
                    || wouldBeDuration > options.maxDuration
                    || gap > options.maxGap {
                    flush()
                }
            }
            current.append(word)

            // Break after sentence-ending punctuation so cues line up with speech.
            if let scalar = word.text.trimmingCharacters(in: .whitespaces).last,
               ".!?。！？".contains(scalar) {
                flush()
            }
        }
        flush()
        return cues
    }

    private static func cuesFromSegments(_ transcript: Transcript) -> [Cue] {
        transcript.segments.enumerated().compactMap { index, segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Cue(index: index + 1, start: segment.start, end: segment.end, text: text)
        }
    }

    /// Wraps a cue into balanced lines.
    ///
    /// Greedy wrapping produces a long line and a stub ("…and precise" / "timestamps").
    /// Subtitles read better when the two lines are close in length, so when the text
    /// fits in two lines we pick the break nearest the middle instead.
    static func wrap(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }

        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1 else { return text }

        // A couple of characters over beats spilling onto a third line.
        if text.count <= limit * 2, let balanced = balancedSplit(words, limit: limit + 3) {
            return balanced
        }

        var lines: [String] = []
        var line = ""
        for word in words {
            if line.isEmpty {
                line = word
            } else if line.count + word.count + 1 <= limit {
                line += " " + word
            } else {
                lines.append(line)
                line = word
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines.joined(separator: "\n")
    }

    /// Finds the word boundary that splits the text into the two most even lines.
    private static func balancedSplit(_ words: [String], limit: Int) -> String? {
        var best: (index: Int, imbalance: Int)?

        for index in 1..<words.count {
            let first = words[..<index].joined(separator: " ")
            let second = words[index...].joined(separator: " ")
            guard first.count <= limit, second.count <= limit else { continue }

            let imbalance = abs(first.count - second.count)
            if best == nil || imbalance < best!.imbalance {
                best = (index, imbalance)
            }
        }

        guard let best else { return nil }
        return words[..<best.index].joined(separator: " ") + "\n" + words[best.index...].joined(separator: " ")
    }

    // MARK: - Serialization

    static func srt(for transcript: Transcript, options: CueOptions = .default) -> String {
        cues(for: transcript, options: options).map { cue in
            """
            \(cue.index)
            \(timecode(cue.start, separator: ",")) --> \(timecode(cue.end, separator: ","))
            \(cue.text)
            """
        }.joined(separator: "\n\n") + "\n"
    }

    static func vtt(for transcript: Transcript, options: CueOptions = .default) -> String {
        let body = cues(for: transcript, options: options).map { cue in
            """
            \(cue.index)
            \(timecode(cue.start, separator: ".")) --> \(timecode(cue.end, separator: "."))
            \(cue.text)
            """
        }.joined(separator: "\n\n")
        return "WEBVTT\n\n" + body + "\n"
    }

    /// Plain text, optionally prefixed with `[hh:mm:ss]` marks per segment.
    static func text(for transcript: Transcript, timestamps: Bool) -> String {
        guard timestamps else { return transcript.paragraphText + "\n" }
        return transcript.segments.compactMap { segment in
            let body = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return "[\(shortTimecode(segment.start))] \(body)"
        }.joined(separator: "\n\n") + "\n"
    }

    /// `hh:mm:ss,mmm` (SRT) or `hh:mm:ss.mmm` (VTT).
    static func timecode(_ seconds: TimeInterval, separator: String) -> String {
        let clamped = max(0, seconds)
        let totalMs = Int((clamped * 1000).rounded())
        let ms = totalMs % 1000
        let totalSeconds = totalMs / 1000
        return String(format: "%02d:%02d:%02d%@%03d",
                      totalSeconds / 3600,
                      (totalSeconds % 3600) / 60,
                      totalSeconds % 60,
                      separator,
                      ms)
    }

    static func shortTimecode(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}
