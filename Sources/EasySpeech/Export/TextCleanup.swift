import AppKit
import Foundation

/// Tidying applied on the way out to a file, never to the stored transcript.
///
/// Export-time on purpose: the transcript keeps every word the recogniser heard, so
/// turning a setting on or off and re-exporting costs nothing. Doing it earlier would
/// mean re-transcribing to get the original back.
enum TextCleanup {

    /// Sounds, not words. Removing these can't damage a sentence, which is the whole
    /// reason the list stops here — "like" and "you know" are real language and need
    /// context to strip safely.
    static let defaultFillers = ["um", "uh", "uhm", "er", "ah", "mm", "hmm", "mhm"]

    static func apply(to transcript: Transcript,
                      removingFillers: Bool,
                      fillers: [String],
                      fixingSpelling: Bool) -> Transcript {
        guard removingFillers || fixingSpelling else { return transcript }
        var copy = transcript
        copy.segments = transcript.segments.map { segment in
            var s = segment
            if removingFillers { s.text = removeFillers(s.text, fillers) }
            if fixingSpelling { s.text = fixSpelling(s.text) }
            // Word timings describe the original audio; once the text is edited they no
            // longer line up with it, and nothing downstream of here reads them.
            s.words = []
            return s
        }
        return copy
    }

    // MARK: - Fillers

    /// Drops whole tokens, so "So, um, I think" loses "um," and keeps both commas' worth
    /// of sentence. Matching ignores case and surrounding punctuation.
    static func removeFillers(_ text: String, _ fillers: [String]) -> String {
        guard !fillers.isEmpty, !text.isEmpty else { return text }
        let drop = Set(fillers.map { $0.lowercased() })

        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            let kept = tokens.filter { !drop.contains(bareWord(String($0))) }
            guard kept.count != tokens.count else { return String(line) }
            var result = kept.joined(separator: " ")
            // A line that used to start with a capital shouldn't start lowercase because
            // the filler in front of it went away.
            if let first = tokens.first, let now = kept.first,
               first.first?.isUppercase == true, now.first?.isLowercase == true {
                result = result.prefix(1).uppercased() + result.dropFirst()
            }
            return result
        }.joined(separator: "\n")
    }

    /// The token with leading and trailing punctuation shaved off, lowercased.
    private static func bareWord(_ token: String) -> String {
        String(token.lowercased().drop(while: { !$0.isLetter && !$0.isNumber })
                    .reversed().drop(while: { !$0.isLetter && !$0.isNumber }).reversed())
    }

    // MARK: - Spelling

    /// `correction(forWordRange:)` is Apple's autocorrect, not its suggestion list: it
    /// returns nil unless it's confident, which is what keeps names and jargon intact.
    /// Verified headless — this needs no `NSApplication`.
    static func fixSpelling(_ text: String, language: String = "en") -> String {
        guard !text.isEmpty else { return text }
        let checker = NSSpellChecker.shared
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }

        var result = text as NSString
        var cursor = 0
        while cursor < result.length {
            let range = checker.checkSpelling(of: result as String, startingAt: cursor)
            guard range.location != NSNotFound, range.length > 0 else { break }
            if let fix = checker.correction(forWordRange: range,
                                            in: result as String,
                                            language: language,
                                            inSpellDocumentWithTag: tag) {
                result = result.replacingCharacters(in: range, with: fix) as NSString
                cursor = range.location + (fix as NSString).length
            } else {
                cursor = range.location + range.length
            }
        }
        return result as String
    }
}
