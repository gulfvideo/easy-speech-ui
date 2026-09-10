import AppKit
import SwiftUI

/// The status-item menu.
///
/// Its reason to exist is live dictation: start it, talk, stop, and the text is on the
/// clipboard — without ever bringing the main window forward.
struct MenuBarView: View {
    @Environment(JobQueue.self) private var queue
    @Environment(LiveTranscriber.self) private var live
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)

        Divider()

        Button(live.isRunning ? "Stop Dictation & Copy" : "Start Dictation") {
            toggleDictation()
        }

        Button("Copy Last Dictation") {
            copy(live.finalizedText)
        }
        .disabled(live.finalizedText.isEmpty)

        Button("Open Live Window…") {
            activate()
            openWindow(id: "live")
        }

        Divider()

        Button("Transcribe Files…") {
            activate()
            FilePicker.presentAndAdd(to: queue)
        }

        if queue.isProcessing {
            Button("Stop Queue") { queue.cancelAll() }
        }

        Divider()

        Button("Open EasySpeech") {
            activate()
            openWindow(id: "main")
        }

        SettingsLink { Text("Settings…") }

        Divider()

        Button("Quit EasySpeech") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        if live.isRunning { return "Listening…" }
        if let progress = queue.modelDownload {
            return "Downloading model — \(Int(progress.fractionCompleted * 100))%"
        }
        if queue.isProcessing {
            let job = queue.activeJob
            if case .transcribing(let fraction) = job?.state {
                return "Transcribing \(Int(fraction * 100))% — \(queue.pendingCount) left"
            }
            return "Working — \(queue.pendingCount) left"
        }
        return "EasySpeech — Idle"
    }

    private func toggleDictation() {
        Task {
            if live.isRunning {
                await live.stop()
                copy(live.finalizedText)
            } else {
                await live.start(localeIdentifier: settings.localeIdentifier)
                // Surface permission or model failures the user can't otherwise see.
                if let error = live.errorMessage { present(error) }
            }
        }
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// A status-item action can fire while the app is in the background; anything that
    /// shows UI needs the app frontmost first.
    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func present(_ message: String) {
        activate()
        let alert = NSAlert()
        alert.messageText = "Couldn't Start Dictation"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension NSImage {
    /// The template status-item mark from EasySpeechArt, tinted by macOS for light/dark.
    static var menuBarIcon: NSImage {
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        let fallback = NSImage(systemSymbolName: "waveform", accessibilityDescription: "EasySpeech")
            ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}
