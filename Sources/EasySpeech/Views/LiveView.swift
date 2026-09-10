import AppKit
import SwiftUI

/// Live microphone transcription in its own window, so it can sit beside the main
/// window while a batch runs.
struct LiveView: View {
    @Environment(LiveTranscriber.self) private var live
    @Environment(AppSettings.self) private var settings

    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(displayText)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .id("body")
                }
                .onChange(of: live.displayText) {
                    guard autoScroll else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("body", anchor: .bottom)
                    }
                }
            }

            if let error = live.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            controls
        }
        .frame(minWidth: 460, minHeight: 320)
        .navigationTitle("Live Transcription")
    }

    /// Volatile text is dimmed so it's clear the engine may still revise it.
    private var displayText: AttributedString {
        var finalized = AttributedString(live.finalizedText)
        finalized.foregroundColor = .labelColor

        guard !live.volatileText.isEmpty else {
            return live.finalizedText.isEmpty
                ? AttributedString("Press Record and start speaking.")
                : finalized
        }

        var volatile = AttributedString((live.finalizedText.isEmpty ? "" : " ") + live.volatileText)
        volatile.foregroundColor = .secondaryLabelColor
        return finalized + volatile
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    if live.isRunning {
                        await live.stop()
                    } else {
                        await live.start(localeIdentifier: settings.localeIdentifier)
                    }
                }
            } label: {
                Label(live.isRunning ? "Stop" : "Record",
                      systemImage: live.isRunning ? "stop.fill" : "record.circle")
                .frame(minWidth: 80)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .controlSize(.large)
            .tint(live.isRunning ? .red : .accentColor)

            if live.isRunning {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Listening").foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            Spacer()

            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)

            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(live.displayText, forType: .string)
            }
            .disabled(live.finalizedText.isEmpty)

            Button("Save…") { save() }
                .disabled(live.finalizedText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .animation(.default, value: live.isRunning)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Live Transcript"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? live.finalizedText.write(to: url, atomically: true, encoding: .utf8)
    }
}
