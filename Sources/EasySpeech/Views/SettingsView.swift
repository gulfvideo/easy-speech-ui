import AppKit
import SwiftUI
import Speech
@preconcurrency import Translation

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            LanguageSettings()
                .tabItem { Label("Languages", systemImage: "globe") }
            TranslationSettings()
                .tabItem { Label("Translation", systemImage: "character.bubble") }
            CorrectionSettings()
                .tabItem { Label("Corrections", systemImage: "character.cursor.ibeam") }
            UpdateSettings()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 560, height: 440)
    }
}

struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(JobQueue.self) private var queue
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section("Menu Bar") {
                Toggle("Show EasySpeech in the menu bar", isOn: $showMenuBarExtra)
                Text("Gives you dictation from anywhere. While it's showing, closing every window leaves EasySpeech running in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Watched Folder") {
                Toggle("Transcribe anything added to a folder", isOn: $settings.watchFolderEnabled)

                HStack {
                    Text(settings.watchFolderPath.isEmpty ? "No folder chosen" : settings.watchFolderPath)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                    Button("Choose…") { chooseWatchFolder() }
                }
                .disabled(!settings.watchFolderEnabled)

                if let problem = queue.watchProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Files already in the folder are left alone — only things added from now on are transcribed, once they've finished copying.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("When a file finishes") {
                Toggle("Reveal output in Finder", isOn: $settings.revealWhenDone)
                Toggle("Open output file", isOn: $settings.openWhenDone)
            }
            Section("Extra formats") {
                LabeledContent("FFmpeg") {
                    if let path = AudioSource.locateFFmpeg() {
                        Label(path.path, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Text("Not installed — .ogg, .opus, .mkv and .wma need it")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseWatchFolder() {
        PanelPresentation.chooseFolder(prompt: "Watch") { settings.watchFolderPath = $0.path }
    }
}

/// Shows which speech models are on the Mac and lets the user pre-download others,
/// so a first run in a new language doesn't stall mid-batch.
struct LanguageSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var entries: [LocaleCatalog.Entry] = []
    @State private var downloading: String?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(entries) { entry in
                HStack {
                    Text(entry.displayName)
                    Spacer()
                    if entry.isInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .labelStyle(.iconOnly)
                    } else if downloading == entry.identifier {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Download") { download(entry) }
                            .buttonStyle(.link)
                    }
                }
                .padding(.vertical, 2)
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        entries = await LocaleCatalog.entries()
    }

    private func download(_ entry: LocaleCatalog.Entry) {
        downloading = entry.identifier
        message = "Downloading \(entry.displayName)…"
        Task {
            defer { downloading = nil }
            do {
                guard let locale = await LocaleCatalog.resolve(entry.identifier) else { return }
                let transcriber = SpeechTranscriberFactory.make(locale: locale)
                try await LocaleCatalog.ensureInstalled(modules: [transcriber])
                await LocaleCatalog.reserve(locale)
                message = "\(entry.displayName) is ready."
                await reload()
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct TranslationSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var configuration: TranslationSession.Configuration?
    @State private var status: String = ""

    var body: some View {
        Form {
            Section("Translation models") {
                Text("Apple downloads each language pair once. Preparing the pair here avoids a pause during a batch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Pair") {
                    Text("\(settings.localeIdentifier) → \(settings.translationTarget)")
                        .font(.callout.monospaced())
                }

                Button("Prepare This Pair") {
                    let source = Locale(identifier: settings.localeIdentifier).language
                    let target = Locale.Language(identifier: settings.translationTarget)
                    configuration = TranslationSession.Configuration(source: source, target: target)
                    status = "Preparing…"
                }

                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        // Presents Apple's own download prompt when the pair isn't installed yet.
        .translationTask(configuration) { session in
            status = await Self.prepare(session)
        }
    }

    /// Runs off the main actor: `prepareTranslation()` is nonisolated, and handing it a
    /// main-actor-isolated session directly is a data race under Swift 6.
    private nonisolated static func prepare(_ session: sending TranslationSession) async -> String {
        do {
            try await session.prepareTranslation()
            return "Ready."
        } catch {
            return error.localizedDescription
        }
    }
}

/// Small indirection so the settings screen doesn't need to know the option sets.
enum SpeechTranscriberFactory {
    static func make(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale,
                               transcriptionOptions: [],
                               reportingOptions: [],
                               attributeOptions: [.audioTimeRange])
    }
}
