import AppKit

/// Presents open/save panels without spinning a modal run loop.
///
/// `runModal()` produces a free-floating window that sinks behind whatever app the user
/// switches to, and blocks the main thread while it's up. Attaching the panel to a window
/// as a sheet keeps it with its document and impossible to lose; when there's no window —
/// the app can be running with only its status item — it falls back to a non-blocking
/// panel rather than a modal one.
enum PanelPresentation {

    @MainActor
    static func present(_ panel: NSSavePanel, completion: @escaping @MainActor (Bool) -> Void) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = anchorWindow {
            panel.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { completion(response == .OK) }
            }
        } else {
            panel.begin { response in
                MainActor.assumeIsolated { completion(response == .OK) }
            }
        }
    }

    /// Prefers the window the user is actually looking at, ignoring panels and popovers.
    @MainActor
    private static var anchorWindow: NSWindow? {
        if let key = NSApp.keyWindow, key.isVisible, !(key is NSPanel) { return key }
        if let main = NSApp.mainWindow, main.isVisible { return main }
        return NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
    }
}
