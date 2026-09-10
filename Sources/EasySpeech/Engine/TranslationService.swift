import Foundation
import Translation

enum TranslationServiceError: LocalizedError {
    case pairUnsupported(String, String)
    case pairNotDownloaded(String, String)

    var errorDescription: String? {
        switch self {
        case .pairUnsupported(let from, let to):
            "Apple can't translate \(from) → \(to)."
        case .pairNotDownloaded(let from, let to):
            "The \(from) → \(to) translation model isn't downloaded yet. Open Settings › Translation and download it."
        }
    }
}

/// On-device translation via Apple's Translation framework.
///
/// Whisper's `--translate` is a property of the acoustic model; Apple separates the two,
/// so we transcribe first and translate the text after. Translating **segment by segment**
/// keeps every timestamp intact, which means translated subtitles still line up.
enum TranslationService {

    static func supportedTargets() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
    }

    static func status(from source: Locale.Language, to target: Locale.Language) async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }

    static func displayName(for language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? "?"
        return (Locale.current.localizedString(forLanguageCode: code) ?? code).capitalizedFirst
    }

    /// Translates each segment, preserving its time range and dropping word timings
    /// (word-level alignment doesn't survive translation).
    static func translate(
        _ transcript: Transcript,
        to target: Locale.Language
    ) async throws -> Transcript {

        let source = Locale(identifier: transcript.localeIdentifier).language

        switch await status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            throw TranslationServiceError.pairNotDownloaded(displayName(for: source), displayName(for: target))
        case .unsupported:
            throw TranslationServiceError.pairUnsupported(displayName(for: source), displayName(for: target))
        @unknown default:
            break
        }

        let session = TranslationSession(installedSource: source, target: target)

        let requests = transcript.segments.enumerated().map { index, segment in
            TranslationSession.Request(sourceText: segment.text, clientIdentifier: String(index))
        }
        guard !requests.isEmpty else { return transcript }

        let responses = try await session.translations(from: requests)

        // Responses can arrive out of order; clientIdentifier maps them back.
        var byIndex: [Int: String] = [:]
        for response in responses {
            if let id = response.clientIdentifier, let index = Int(id) {
                byIndex[index] = response.targetText
            }
        }

        var translated = transcript
        translated.segments = transcript.segments.enumerated().map { index, segment in
            var copy = segment
            copy.text = byIndex[index] ?? segment.text
            copy.words = []
            return copy
        }
        translated.translatedText = translated.paragraphText
        return translated
    }
}
