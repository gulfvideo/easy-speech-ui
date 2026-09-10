import AppKit
import SwiftUI

/// The options panel. Every control here changes real output — there are no
/// engine-tuning knobs, because Apple manages model selection itself.
struct InspectorView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Output Files") {
                Toggle("Plain text (.txt)", isOn: $settings.writeText)
                Toggle("Subtitles (.srt)", isOn: $settings.writeSRT)
                Toggle("Web subtitles (.vtt)", isOn: $settings.writeVTT)

                Toggle("Timestamp each paragraph", isOn: $settings.timestampsInText)
                    .disabled(!settings.writeText)

                if settings.outputLocation != .none && !settings.writeText && !settings.writeSRT && !settings.writeVTT {
                    Label("No file will be written.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Save To") {
                Picker("Location", selection: $settings.outputLocation) {
                    ForEach(OutputLocation.allCases) { location in
                        Text(location.label).tag(location)
                    }
                }
                .labelsHidden()

                if settings.outputLocation == .customFolder {
                    HStack {
                        Text(folderLabel)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                        Button("Choose…") { chooseFolder() }
                    }
                }

                Toggle("Reveal in Finder when done", isOn: $settings.revealWhenDone)
                Toggle("Open when done", isOn: $settings.openWhenDone)
            }

            Section("Translation") {
                Toggle("Translate transcript", isOn: $settings.translate)
                TranslationTargetPicker()
                    .disabled(!settings.translate)
                Text("Apple transcribes in the spoken language first, then translates. Timestamps are preserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recognition") {
                LanguagePicker()
                Toggle("Mask profanity", isOn: $settings.censorProfanity)
                Text("Punctuation and capitalization are applied automatically by Apple's model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 260)
    }

    private var folderLabel: String {
        settings.customOutputPath.isEmpty ? "No folder chosen"
                                          : (settings.customOutputURL?.path ?? "")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        PanelPresentation.present(panel) { accepted in
            guard accepted, let url = panel.url else { return }
            settings.customOutputPath = url.path
        }
    }
}

struct TranslationTargetPicker: View {
    @Environment(AppSettings.self) private var settings
    @State private var languages: [Locale.Language] = []

    var body: some View {
        @Bindable var settings = settings

        Picker("Translate to", selection: $settings.translationTarget) {
            if languages.isEmpty {
                Text("English").tag("en")
            }
            ForEach(languages, id: \.self) { language in
                Text(TranslationService.displayName(for: language))
                    .tag(language.languageCode?.identifier ?? "en")
            }
        }
        .task {
            let all = await TranslationService.supportedTargets()
            // Collapse regional variants; the picker only needs the language.
            var seen = Set<String>()
            languages = all.filter { language in
                guard let code = language.languageCode?.identifier else { return false }
                return seen.insert(code).inserted
            }
            .sorted {
                TranslationService.displayName(for: $0)
                    .localizedStandardCompare(TranslationService.displayName(for: $1)) == .orderedAscending
            }
        }
    }
}
