import Foundation
import Speech

/// Wraps `AssetInventory`, which downloads a language's acoustic model if it isn't
/// already present. The assets are system-managed and shared with Dictation, so they
/// never appear in the app's own storage and don't need version tracking here.
enum LocaleCatalog {

    struct Entry: Identifiable, Hashable, Sendable {
        var id: String { identifier }
        let identifier: String
        let displayName: String
        let isInstalled: Bool
    }

    /// All supported locales with a friendly name and install state, sorted for display.
    static func entries() async -> [Entry] {
        let supported = await SpeechTranscriber.supportedLocales
        let installed = Set(await SpeechTranscriber.installedLocales.map(\.normalizedIdentifier))

        return supported.map { locale in
            Entry(identifier: locale.normalizedIdentifier,
                  displayName: displayName(for: locale),
                  isInstalled: installed.contains(locale.normalizedIdentifier))
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    static func displayName(for locale: Locale) -> String {
        let current = Locale.current
        let language = locale.language.languageCode?.identifier ?? locale.identifier
        let base = current.localizedString(forLanguageCode: language) ?? language
        if let region = locale.region?.identifier,
           let regionName = current.localizedString(forRegionCode: region) {
            return "\(base.capitalizedFirst) (\(regionName))"
        }
        return base.capitalizedFirst
    }

    /// Finds the closest supported locale to what the user asked for.
    static func resolve(_ identifier: String) async -> Locale? {
        let requested = Locale(identifier: identifier)
        if let exact = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            return exact
        }
        // Fall back to any region variant of the same language, e.g. "de" -> "de-DE".
        guard let code = requested.language.languageCode?.identifier else { return nil }
        return await SpeechTranscriber.supportedLocales.first {
            $0.language.languageCode?.identifier == code
        }
    }

    /// Downloads the on-device assets for these modules if they aren't present yet.
    static func ensureInstalled(
        modules: [any SpeechModule],
        progress: (@Sendable (Progress) -> Void)? = nil
    ) async throws {
        let status = await AssetInventory.status(forModules: modules)
        guard status != .installed else { return }

        guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else {
            // Nothing to install — the system considers the modules ready.
            return
        }
        progress?(request.progress)
        try await request.downloadAndInstall()
    }

    /// Keeps a locale's assets from being reclaimed by the system. Up to 5 may be held.
    @discardableResult
    static func reserve(_ locale: Locale) async -> Bool {
        do {
            let reserved = await AssetInventory.reservedLocales
            if reserved.contains(where: { $0.normalizedIdentifier == locale.normalizedIdentifier }) {
                return true
            }
            if reserved.count >= AssetInventory.maximumReservedLocales, let oldest = reserved.last {
                _ = await AssetInventory.release(reservedLocale: oldest)
            }
            return try await AssetInventory.reserve(locale: locale)
        } catch {
            return false
        }
    }
}

extension Locale {
    /// `en_US` and `en-US` both occur in these APIs; normalize to dashes.
    var normalizedIdentifier: String {
        identifier.replacingOccurrences(of: "_", with: "-")
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
