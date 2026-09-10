import AppKit
import SwiftUI

/// The sheet shown when an update is available or being installed.
struct UpdateSheet: View {
    @Environment(UpdateController.self) private var updates
    @Environment(\.dismiss) private var dismiss

    let update: AvailableUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text("EasySpeech \(update.version) is available")
                        .font(.headline)
                    Text("You have \(updates.currentVersion). The download is \(byteLabel).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                Text(LocalizedStringKey(update.notes.isEmpty ? "No release notes." : update.notes))
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(height: 240)

            Divider()
            footer
        }
        .frame(width: 520)
    }

    @ViewBuilder
    private var footer: some View {
        switch updates.state {
        case .installing(let stage):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(label(for: stage)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(16)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("View on GitHub") { NSWorkspace.shared.open(update.releasePage) }
                    Spacer()
                    Button("Close") { updates.dismiss(); dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)

        default:
            HStack(spacing: 12) {
                Button("Release Notes") { NSWorkspace.shared.open(update.releasePage) }
                Spacer()
                Button("Not Now") { updates.dismiss(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Update and Relaunch") { updates.install(update) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }

    private var byteLabel: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(update.byteCount))
    }

    private func label(for stage: Updater.Stage) -> String {
        switch stage {
        case .downloading: "Downloading…"
        case .verifying: "Verifying the download…"
        case .installing: "Installing…"
        case .relaunching: "Relaunching…"
        }
    }
}

/// The Updates tab in Settings.
struct UpdateSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UpdateController.self) private var updates

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                LabeledContent("Version") {
                    Text(updates.currentVersion).font(.callout.monospaced())
                }

                Toggle("Check for updates automatically", isOn: $settings.automaticUpdateChecks)

                LabeledContent("Last checked") {
                    Text(lastCheckedLabel).foregroundStyle(.secondary).font(.callout)
                }

                HStack {
                    Button("Check Now") { updates.check(userInitiated: true) }
                        .disabled(updates.isBusy)
                    if updates.isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Releases on GitHub") {
                        NSWorkspace.shared.open(UpdateChecker.releasesPage)
                    }
                    .buttonStyle(.link)
                }

                switch updates.state {
                case .upToDate:
                    Label("EasySpeech is up to date.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                case .available(let update):
                    Label("Version \(update.version) is available.", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.callout)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                default:
                    EmptyView()
                }
            }

            Section {
                Text("""
                Updates are downloaded from the project's GitHub releases over HTTPS and \
                checked against the SHA-256 checksum GitHub publishes for the file. A download \
                that doesn't match, or that isn't EasySpeech, is discarded rather than installed.

                Because EasySpeech downloads the update itself, macOS doesn't quarantine it — \
                you won't have to repeat the Privacy & Security approval you did on first install.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var lastCheckedLabel: String {
        guard let date = settings.lastUpdateCheck else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
