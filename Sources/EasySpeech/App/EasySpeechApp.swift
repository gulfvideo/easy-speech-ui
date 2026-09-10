import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct EasySpeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @State private var queue = JobQueue()
    @State private var live = LiveTranscriber()
    @State private var settings = AppSettings.shared

    var body: some Scene {
        Window("EasySpeech", id: "main") {
            ContentView()
                .environment(queue)
                .environment(live)
                .environment(settings)
                .onAppear { delegate.queue = queue }
        }
        .defaultSize(width: 1000, height: 680)
        .commands { AppCommands(queue: queue, live: live) }

        Window("Live Transcription", id: "live") {
            LiveView()
                .environment(live)
                .environment(settings)
        }
        .defaultSize(width: 620, height: 440)
        .keyboardShortcut("l", modifiers: [.command, .shift])

        Settings {
            SettingsView()
                .environment(settings)
        }

        MenuBarExtra(isInserted: Bindable(settings).showMenuBarExtra) {
            MenuBarView()
                .environment(queue)
                .environment(live)
                .environment(settings)
        } label: {
            Image(nsImage: .menuBarIcon)
        }
    }
}

/// Handles Finder "Open With" and drops onto the Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var queue: JobQueue?
    /// Files that arrive before the window exists are held until it does.
    @MainActor private var pending: [URL] = []

    /// With the status item showing, closing every window leaves the app running the way
    /// a menu bar utility should. Without it, the app has no UI left, so it quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { !AppSettings.shared.showMenuBarExtra }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            if let queue {
                queue.add(urls)
            } else {
                pending.append(contentsOf: urls)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let queue, !pending.isEmpty else { return }
            queue.add(pending)
            pending.removeAll()
        }
    }
}
