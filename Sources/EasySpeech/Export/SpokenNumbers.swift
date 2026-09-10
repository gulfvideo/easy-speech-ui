import Foundation

/// Repairs Apple's inverse text normalization where it hurts readability.
///
/// `SpeechTranscriber` converts spoken quantities to digits very literally, so
/// "millions of people" comes back as "1000000s of people", "twenty million" as
/// "20000000", and "a thousand years old" as "a 1000 years old". The values are correct
/// but hard to read as prose. These rules only touch forms that are unambiguously
/// artifacts — years, phone numbers and ordinary counts like "100 companies" or
/// "100% correct" are deliberately left alone.
enum SpokenNumbers {

    private static let scales: [(value: Int, singular: String, plural: String)] = [
        (1_000_000_000, "billion", "billions"),
        (1_000_000, "million", "millions"),
        (1_000, "thousand", "thousands")
    ]

    static func polish(_ text: String) -> String {
        // Every rule below keys off a digit. Skipping digit-free text early avoids five
        // regex passes over ~99% of the tokens in a typical transcript.
        guard text.contains(where: \.isNumber) else { return text }

        var result = text
        result = replacePluralizedScales(in: result)
        result = replaceLargeRoundNumbers(in: result)
        result = replaceArticleQuantities(in: result)
        result = replaceSmallOrdinals(in: result)
        result = groupCurrencyDigits(in: result)
        return result
    }

    private static let smallOrdinals: [String: String] = [
        "1st": "first", "2nd": "second", "3rd": "third", "4th": "fourth", "5th": "fifth",
        "6th": "sixth", "7th": "seventh", "8th": "eighth", "9th": "ninth"
    ]

    /// "the 1st version" → "the first version".
    ///
    /// Only single-digit ordinals, following the usual convention that ordinals below ten
    /// are spelled out in prose and larger ones aren't. A date keeps its digits: "May 1st"
    /// is left alone, because "May first" reads like a mistake.
    ///
    /// `\b([1-9])` can't match inside a longer number, so 11th, 21st and 103rd are all
    /// untouched without needing a rule of their own.
    private static let ordinalPattern: NSRegularExpression = {
        let months = "Jan|January|Feb|February|Mar|March|Apr|April|May|Jun|June|Jul|July"
            + "|Aug|August|Sep|Sept|September|Oct|October|Nov|November|Dec|December"
        return compile("(\\b(?:\(months))\\.?\\s+)?\\b([1-9](?:st|nd|rd|th))\\b")
    }()

    private static func replaceSmallOrdinals(in text: String) -> String {
        replaceMatches(with: ordinalPattern, in: text) { groups in
            // Group 1 present means a month preceded it — that's a date, leave it.
            guard groups[1].isEmpty else { return nil }
            return smallOrdinals[groups[2].lowercased()]
        }
    }

    /// "1000000s" → "millions". Nobody writes a plural on a digit string, so any match
    /// here is an artifact.
    private static let pluralizedScalePattern = compile("\\b([0-9]{4,})s\\b")

    private static func replacePluralizedScales(in text: String) -> String {
        replaceMatches(with: pluralizedScalePattern, in: text) { groups in
            guard let value = Int(groups[1]) else { return nil }
            return scales.first { $0.value == value }?.plural
        }
    }

    /// "20000000" → "20 million". Only exact multiples of a scale, and only from a
    /// million up, so "1000" and "$1000" keep their digits.
    private static let largeRoundPattern = compile("\\b([0-9]{7,})\\b")

    private static func replaceLargeRoundNumbers(in text: String) -> String {
        replaceMatches(with: largeRoundPattern, in: text) { groups in
            guard let value = Int(groups[1]) else { return nil }
            for scale in scales where scale.value >= 1_000_000 {
                if value % scale.value == 0 {
                    let count = value / scale.value
                    return "\(count) \(scale.singular)"
                }
            }
            return nil
        }
    }

    /// "a 1000 years old" → "a thousand years old".
    private static let articleQuantityPattern = compile("\\b(a|A|an|An)\\s+([0-9]{3,})\\b")

    private static func replaceArticleQuantities(in text: String) -> String {
        replaceMatches(with: articleQuantityPattern, in: text) { groups in
            guard let value = Int(groups[2]) else { return nil }
            let word: String? = switch value {
            case 100: "hundred"
            case 1_000: "thousand"
            case 1_000_000: "million"
            case 1_000_000_000: "billion"
            default: nil
            }
            guard let word else { return nil }
            return "\(groups[1]) \(word)"
        }
    }

    /// "$1000" → "$1,000". Currency is explicit, so grouping is safe here in a way it
    /// is not for a bare four-digit number that might be a year or an extension.
    private static let currencyPattern = compile("\\$([0-9]{4,})\\b")

    /// NumberFormatter is expensive to build, and this one never varies.
    private static let groupingFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private static func groupCurrencyDigits(in text: String) -> String {
        replaceMatches(with: currencyPattern, in: text) { groups in
            guard let value = Int(groups[1]),
                  let grouped = groupingFormatter.string(from: NSNumber(value: value)) else { return nil }
            return "$\(grouped)"
        }
    }

    /// Patterns are fixed literals, so a failure here is a programming error, not input.
    private static func compile(_ pattern: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }

    /// Applies `transform` to each match; returning nil leaves that match as-is.
    private static func replaceMatches(
        with regex: NSRegularExpression,
        in text: String,
        transform: ([String]) -> String?
    ) -> String {
        let full = NSRange(text.startIndex..., in: text)
        // Bail before allocating anything when the pattern doesn't appear.
        guard regex.firstMatch(in: text, range: full) != nil else { return text }
        var result = text

        // Replace back-to-front so earlier ranges stay valid.
        for match in regex.matches(in: text, range: full).reversed() {
            var groups: [String] = []
            for index in 0..<match.numberOfRanges {
                guard let range = Range(match.range(at: index), in: text) else {
                    groups.append("")
                    continue
                }
                groups.append(String(text[range]))
            }
            guard let replacement = transform(groups),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
