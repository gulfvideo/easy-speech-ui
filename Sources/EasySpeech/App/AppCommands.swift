import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The command model, built before the screens — every important action lives in the
/// menu bar with a shortcut, not only behind a toolbar icon.
struct AppCommands: Commands {
    let queue: JobQueue
    let live: LiveTranscriber
    let updates: UpdateController

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updates.check(userInitiated: true) }
                .disabled(updates.isBusy)
        }

        CommandGroup(replacing: .newItem) {
            Button("Open…") { FilePicker.presentAndAdd(to: queue) }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .saveItem) {
            Button("Export Transcript…") {
                NotificationCenter.default.post(name: .exportTranscript, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Reveal Output in Finder") {
                NotificationCenter.default.post(name: .revealOutput, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandMenu("Transcribe") {
            Button("Start Queue") { queue.startIfIdle() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(queue.isProcessing || queue.pendingCount == 0)

            Button(queue.isPaused ? "Resume Queue" : "Pause Queue") {
                queue.isPaused ? queue.resume() : queue.pause()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!queue.isProcessing)

            Button("Stop") { queue.cancelAll() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!queue.isProcessing)

            Divider()

            Button(live.isRunning ? "Stop Live Transcription" : "Live Transcription…") {
                openWindow(id: "live")
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            // Also in the Options inspector, but the menu keeps it reachable with the
            // inspector closed — and gives it keyboard navigation.
            LanguagePicker()

            Divider()

            Button("Clear Finished") { queue.clearFinished() }
                .disabled(!queue.jobs.contains { $0.state.isTerminal })
        }

        CommandGroup(replacing: .help) {
            Link("EasySpeech on GitHub",
                 destination: URL(string: "https://github.com/gulfvideo/easy-speech-ui")!)
        }
    }
}

extension Notification.Name {
    static let exportTranscript = Notification.Name("EasySpeech.exportTranscript")
    static let revealOutput = Notification.Name("EasySpeech.revealOutput")
}

enum FilePicker {
    /// Standard open panel, restricted to media the app can actually decode.
    ///
    /// Presented as a sheet when there's a window to attach it to, and otherwise as an
    /// ordinary panel — never with `runModal()`. Running a modal loop from the menu bar
    /// left the panel floating free, where it sank behind whatever app was in front while
    /// the status menu carried on opening over the top of it.
    @MainActor
    static func presentAndAdd(to queue: JobQueue) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose audio or video files to transcribe."
        panel.prompt = "Transcribe"
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie, .mp3, .wav, .aiff, .quickTimeMovie]

        NSApp.activate(ignoringOtherApps: true)

        // A sheet belongs to a window; only fall back to a free panel without one.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK else { return }
                queue.add(panel.urls)
            }
        } else {
            panel.begin { response in
                guard response == .OK else { return }
                MainActor.assumeIsolated {
                    _ = queue.add(panel.urls)
                }
            }
        }
    }
}
