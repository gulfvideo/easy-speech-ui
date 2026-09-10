import Foundation

/// One "the recognizer hears X, it should say Y" rule.
struct Correction: Codable, Hashable, Identifiable, Sendable {
    var id: String { heard.lowercased() }
    /// What the recognizer actually produces, e.g. "Ensure if I".
    var heard: String
    /// What it should say, e.g. "Ensurify".
    var replacement: String
}

/// Applies the user's correction rules to recognized text.
///
/// Deliberately exact rather than fuzzy. An earlier edit-distance version fixed the real
/// mis-hearings but also rewrote "The weather institute" into a listed name and swallowed
/// the word "with" — for captioning, a confident wrong correction is worse than a missed
/// one. Rules only fire on what the user actually typed.
///
/// Matching ignores case and treats runs of whitespace as equivalent, because the
/// recognizer's word splitting is exactly what's being corrected. Matches must fall on
/// word boundaries, so a rule for "Ann" never fires inside "channel".
enum VocabularyCorrector {

    static func correct(_ text: String, using corrections: [Correction]) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        // Longest first: a rule for "Ensure if I" should win over one for "Ensure".
        for rule in corrections.sorted(by: { $0.heard.count > $1.heard.count }) {
            result = apply(rule, to: result)
        }
        return result
    }

    private static func apply(_ rule: Correction, to text: String) -> String {
        let heard = rule.heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else { return text }

        // Whitespace in the rule matches any run of whitespace in the transcript, since
        // the recognizer's word splitting is part of what's being corrected. Spaces are
        // not regex metacharacters, so escapedPattern leaves them as-is.
        let escaped = heard
            .split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: "\\s+")
        // Only anchor on word boundaries where the edge is actually a word character;
        // \b next to punctuation would refuse to match.
        let leading = heard.first.map(isWordish) == true ? "\\b" : ""
        let trailing = heard.last.map(isWordish) == true ? "\\b" : ""

        guard let regex = try? NSRegularExpression(pattern: leading + escaped + trailing,
                                                   options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let template = NSRegularExpression.escapedTemplate(for: rule.replacement)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func isWordish(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
