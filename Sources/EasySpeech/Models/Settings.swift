import AppKit
import Foundation
import Observation

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil hands control back to the system setting.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum OutputLocation: String, CaseIterable, Identifiable, Sendable {
    case alongsideSource
    case customFolder
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alongsideSource: "Alongside original file"
        case .customFolder: "Choose a folder…"
        case .none: "Don't write files"
        }
    }
}

/// User-facing options, persisted in UserDefaults.
///
/// Apple selects and updates the acoustic model itself, so there is no model-size or
/// engine-flag setting to expose. What remains are the options that actually change
/// what lands on disk.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: Recognition

    var localeIdentifier: String {
        didSet { defaults.set(localeIdentifier, forKey: "localeIdentifier") }
    }
    /// Apple's `etiquetteReplacements` — masks profanity as e.g. "s---".
    var censorProfanity: Bool {
        didSet { defaults.set(censorProfanity, forKey: "censorProfanity") }
    }

    /// Applied to the whole app, so window chrome and menus follow it too — not just
    /// the SwiftUI hierarchy the way `preferredColorScheme` would.
    var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

    func applyAppearance() {
        NSApp?.appearance = appearance.nsAppearance
    }

    // MARK: Output

    var writeText: Bool {
        didSet { defaults.set(writeText, forKey: "writeText") }
    }
    var writeSRT: Bool {
        didSet { defaults.set(writeSRT, forKey: "writeSRT") }
    }
    var writeVTT: Bool {
        didSet { defaults.set(writeVTT, forKey: "writeVTT") }
    }
    var timestampsInText: Bool {
        didSet { defaults.set(timestampsInText, forKey: "timestampsInText") }
    }
    var outputLocation: OutputLocation {
        didSet { defaults.set(outputLocation.rawValue, forKey: "outputLocation") }
    }
    var customOutputPath: String {
        didSet { defaults.set(customOutputPath, forKey: "customOutputPath") }
    }
    var revealWhenDone: Bool {
        didSet { defaults.set(revealWhenDone, forKey: "revealWhenDone") }
    }
    var openWhenDone: Bool {
        didSet { defaults.set(openWhenDone, forKey: "openWhenDone") }
    }

    /// Keeps the status item in the menu bar, and keeps the app alive without windows.
    /// Owned by `@AppStorage` in the App and Settings scenes — read here, never cached,
    /// so the AppDelegate always sees the current value.
    var showMenuBarExtra: Bool {
        defaults.bool(forKey: "showMenuBarExtra")
    }

    /// "The recognizer hears X, it should say Y" rules, applied to every transcript.
    /// The replacements are also offered to the analyzer as contextual strings.
    var corrections: [Correction] {
        didSet {
            if let data = try? JSONEncoder().encode(corrections) {
                defaults.set(data, forKey: "corrections")
            }
        }
    }

    /// The corrected spellings, for biasing recognition.
    var vocabulary: [String] { corrections.map(\.replacement) }

    // MARK: Watched folder

    var watchFolderEnabled: Bool {
        didSet { defaults.set(watchFolderEnabled, forKey: "watchFolderEnabled") }
    }
    var watchFolderPath: String {
        didSet { defaults.set(watchFolderPath, forKey: "watchFolderPath") }
    }

    var watchFolderURL: URL? {
        guard watchFolderEnabled, !watchFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: watchFolderPath)
    }

    /// UID of the input device for live dictation. Empty means the system default.
    /// Stored by UID because CoreAudio device ids are reassigned when hardware moves.
    var inputDeviceUID: String {
        didSet { defaults.set(inputDeviceUID, forKey: "inputDeviceUID") }
    }

    // MARK: Updates

    var automaticUpdateChecks: Bool {
        didSet { defaults.set(automaticUpdateChecks, forKey: "automaticUpdateChecks") }
    }
    var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: "lastUpdateCheck") }
    }

    // MARK: Translation

    var translate: Bool {
        didSet { defaults.set(translate, forKey: "translate") }
    }
    var translationTarget: String {
        didSet { defaults.set(translationTarget, forKey: "translationTarget") }
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    var customOutputURL: URL? {
        guard outputLocation == .customFolder, !customOutputPath.isEmpty else { return nil }
        return URL(fileURLWithPath: customOutputPath)
    }

    /// At least one format must stay on, otherwise a run produces nothing on disk.
    var writesAnyFile: Bool {
        outputLocation != .none && (writeText || writeSRT || writeVTT)
    }

    private init() {
        defaults.register(defaults: [
            "writeText": true,
            "writeSRT": false,
            "writeVTT": false,
            "timestampsInText": false,
            "revealWhenDone": false,
            "showMenuBarExtra": true,
            "openWhenDone": false,
            "censorProfanity": false,
            "translate": false,
            "outputLocation": OutputLocation.alongsideSource.rawValue,
            "translationTarget": "en",
            "appearance": AppAppearance.system.rawValue,
            "automaticUpdateChecks": true
        ])

        localeIdentifier = defaults.string(forKey: "localeIdentifier")
            ?? Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        censorProfanity = defaults.bool(forKey: "censorProfanity")
        writeText = defaults.bool(forKey: "writeText")
        writeSRT = defaults.bool(forKey: "writeSRT")
        writeVTT = defaults.bool(forKey: "writeVTT")
        timestampsInText = defaults.bool(forKey: "timestampsInText")
        outputLocation = OutputLocation(rawValue: defaults.string(forKey: "outputLocation") ?? "")
            ?? .alongsideSource
        customOutputPath = defaults.string(forKey: "customOutputPath") ?? ""
        revealWhenDone = defaults.bool(forKey: "revealWhenDone")
        openWhenDone = defaults.bool(forKey: "openWhenDone")
        translate = defaults.bool(forKey: "translate")
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        watchFolderEnabled = defaults.bool(forKey: "watchFolderEnabled")
        watchFolderPath = defaults.string(forKey: "watchFolderPath") ?? ""
        corrections = (defaults.data(forKey: "corrections"))
            .flatMap { try? JSONDecoder().decode([Correction].self, from: $0) } ?? []
        inputDeviceUID = defaults.string(forKey: "inputDeviceUID") ?? ""
        automaticUpdateChecks = defaults.bool(forKey: "automaticUpdateChecks")
        lastUpdateCheck = defaults.object(forKey: "lastUpdateCheck") as? Date
        translationTarget = defaults.string(forKey: "translationTarget") ?? "en"
    }
}
