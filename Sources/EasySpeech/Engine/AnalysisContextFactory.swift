import Foundation
import Speech

/// Builds the `AnalysisContext` that biases recognition toward a user's own vocabulary.
///
/// Proper nouns are where transcription errors concentrate — names of people, places,
/// programmes and products the model has no reason to expect. Contextual strings tell the
/// recognizer those spellings are likely, which fixes them at the source rather than with
/// find-and-replace afterwards.
enum AnalysisContextFactory {

    /// Apple treats these as hints, not rules; an unbounded list dilutes each entry.
    static let maximumTerms = 500

    static func make(from vocabulary: [String]) -> AnalysisContext? {
        let terms = normalize(vocabulary)
        guard !terms.isEmpty else { return nil }

        let context = AnalysisContext()
        context.contextualStrings = [.general: terms]
        return context
    }

    /// Trims, drops blanks, removes case-insensitive duplicates, and caps the list.
    static func normalize(_ vocabulary: [String]) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []

        for entry in vocabulary {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard seen.insert(trimmed.lowercased()).inserted else { continue }
            terms.append(trimmed)
            if terms.count == maximumTerms { break }
        }
        return terms
    }
}
