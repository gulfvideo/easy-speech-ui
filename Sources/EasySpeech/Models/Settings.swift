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

    // MARK: Batch

    /// How many files transcribe at once, 1...6.
    ///
    /// One stream does not saturate the Neural Engine. Measured on an M5 Pro over 30-minute
    /// files: 72x realtime at 1, 207x at 4, 255x at 6, and it falls off again at 8. Individual
    /// files get slower, the batch finishes sooner.
    /// Never clamp by assigning to this property inside its own `didSet`. `@Observable`
    /// rewrites a stored property into a computed one, which removes Swift's usual
    /// suppression of re-entry, so the assignment calls the setter again and recurses until
    /// the stack runs out. That shipped in 1.2.6 and crashed the app on every change.
    /// Clamping happens where the value is read instead: `init`, and `JobQueue.drain`.
    var concurrentJobs: Int {
        didSet { defaults.set(concurrentJobs, forKey: "concurrentJobs") }
    }

    static let concurrencyRange = 1...6

    static func clampConcurrency(_ value: Int) -> Int {
        min(max(value, concurrencyRange.lowerBound), concurrencyRange.upperBound)
    }

    /// Skip a file when everything it would write is already sitting in the destination.
    /// Lets a folder be re-run after an interruption without redoing what finished.
    var skipAlreadyTranscribed: Bool {
        didSet { defaults.set(skipAlreadyTranscribed, forKey: "skipAlreadyTranscribed") }
    }

    /// The file extensions a run would currently produce.
    var enabledOutputExtensions: [String] {
        var exts: [String] = []
        if writeText { exts.append("txt") }
        if writeSRT { exts.append("srt") }
        if writeVTT { exts.append("vtt") }
        return exts
    }

    /// Where `source` would be written, honouring the custom-folder setting.
    func outputFolder(for source: URL) -> URL {
        customOutputURL ?? source.deletingLastPathComponent()
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
        // Only the settings that default to *on* need registering: `bool(forKey:)`
        // already returns false for a missing key, and the rest fall back below.
        defaults.register(defaults: [
            "writeText": true,
            "showMenuBarExtra": true,
            "skipAlreadyTranscribed": true,
            "concurrentJobs": 1,
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
        concurrentJobs = Self.clampConcurrency(defaults.integer(forKey: "concurrentJobs"))
        skipAlreadyTranscribed = defaults.bool(forKey: "skipAlreadyTranscribed")
        automaticUpdateChecks = defaults.bool(forKey: "automaticUpdateChecks")
        lastUpdateCheck = defaults.object(forKey: "lastUpdateCheck") as? Date
        translationTarget = defaults.string(forKey: "translationTarget") ?? "en"
    }
}
