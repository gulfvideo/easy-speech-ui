import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(JobQueue.self) private var queue
    @Environment(AppSettings.self) private var settings
    @Environment(UpdateController.self) private var updates
    @Environment(\.openWindow) private var openWindow

    @State private var selection: Job.ID?
    @State private var isDropTargeted = false
    @AppStorage("showInspector") private var showInspector = true
    @AppStorage("sidebarWidth") private var sidebarWidth = 280.0

    private var selectedJob: Job? {
        queue.jobs.first { $0.id == selection } ?? queue.activeJob ?? queue.jobs.last
    }

    var body: some View {
        NavigationSplitView {
            JobListView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: sidebarWidth, max: 420)
        } detail: {
            TranscriptView(job: selectedJob)
                .toolbar { contentToolbar }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                .toolbar { inspectorToolbar }
        }
        .dropDestination(for: URL.self) { urls, _ in
            queue.add(urls) > 0
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle("EasySpeech")
        .navigationSubtitle(subtitle)
        .onReceive(NotificationCenter.default.publisher(for: .revealOutput)) { _ in
            revealSelected()
        }
        .onAppear { queue.syncFolderWatch() }
        .onChange(of: settings.watchFolderEnabled) { queue.syncFolderWatch() }
        .onChange(of: settings.watchFolderPath) { queue.syncFolderWatch() }
        .sheet(item: Bindable(updates).pendingPrompt) { update in
            UpdateSheet(update: update)
                .environment(updates)
                .environment(queue)
        }
    }

    private var subtitle: String {
        if let progress = queue.modelDownload {
            return "Downloading language model — \(Int(progress.fractionCompleted * 100))%"
        }
        if queue.isProcessing {
            let remaining = queue.pendingCount
            return remaining > 1 ? "Transcribing — \(remaining) files left" : "Transcribing"
        }
        let done = queue.jobs.filter { $0.state == .finished }.count
        // Say so when files were dropped, otherwise adding a folder of finished work
        // looks like nothing happened at all.
        let skipped = queue.lastSkippedCount
        if skipped > 0 {
            let already = "\(skipped) already transcribed"
            return done > 0 ? "\(done) transcribed · \(already)" : already
        }
        return done > 0 ? "\(done) transcribed" : "Ready"
    }

    /// Content actions attach to the detail column, not to the split view, so they stay
    /// inside the content region instead of right-aligning across the whole window and
    /// spilling over the inspector's divider when it's open. That region is narrow when
    /// the inspector is showing, so it holds actions only — the language picker lives in
    /// the inspector and in the Transcribe menu, both of which suit it better anyway.
    ///
    /// macOS 26 also fuses adjacent toolbar items into one shared-background capsule.
    /// Three unlabelled glyphs in a single pill read as one mystery segmented control,
    /// so the action buttons carry titles and Add Files gets its own background.
    @ToolbarContentBuilder
    private var contentToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                FilePicker.presentAndAdd(to: queue)
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .help("Add audio or video files (⌘O)")
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            if queue.isProcessing {
                Button(role: .destructive) {
                    queue.cancelAll()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .labelStyle(.titleAndIcon)
                .help("Stop transcribing (⌘.)")
            } else {
                Button {
                    queue.startIfIdle()
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .labelStyle(.titleAndIcon)
                .disabled(queue.pendingCount == 0)
                .help("Start the queue (⌘R)")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                openWindow(id: "live")
            } label: {
                Label("Live", systemImage: "mic.fill")
            }
            .labelStyle(.titleAndIcon)
            .help("Live microphone transcription (⇧⌘L)")
        }

    }

    /// Lives on the inspector so macOS keeps it pinned to the trailing edge.
    @ToolbarContentBuilder
    private var inspectorToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showInspector.toggle()
            } label: {
                Label("Options", systemImage: "sidebar.trailing")
            }
            .help("Show or hide options")
        }
    }

    private func revealSelected() {
        guard let job = selectedJob, !job.outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(job.outputs)
    }
}

/// Toolbar language selector, showing which models are already on the Mac.
struct LanguagePicker: View {
    /// Bound to the shared object rather than the environment so this works inside a
    /// menu-bar command, which doesn't inherit the window's environment.
    @State private var settings = AppSettings.shared
    @State private var entries: [LocaleCatalog.Entry] = []

    /// The current selection is always present as an option. A SwiftUI Picker whose
    /// selection matches no tag renders completely blank, which is what happens during
    /// the moment before the locale list loads.
    private var options: [LocaleCatalog.Entry] {
        if entries.contains(where: { $0.identifier == settings.localeIdentifier }) {
            return entries
        }
        let current = LocaleCatalog.Entry(
            identifier: settings.localeIdentifier,
            displayName: LocaleCatalog.displayName(for: Locale(identifier: settings.localeIdentifier)),
            isInstalled: false
        )
        return [current] + entries
    }

    var body: some View {
        @Bindable var settings = settings

        Picker(selection: $settings.localeIdentifier) {
            ForEach(options) { entry in
                Text(entry.isInstalled ? entry.displayName : "\(entry.displayName) ⤓")
                    .tag(entry.identifier)
            }
        } label: {
            Text("Language")
        }
        .pickerStyle(.menu)
        .help("Spoken language. ⤓ marks languages Apple will download on first use.")
        .task {
            entries = await LocaleCatalog.entries()
            // Snap a stale or region-less selection onto a real supported locale.
            if !entries.contains(where: { $0.identifier == settings.localeIdentifier }),
               let resolved = await LocaleCatalog.resolve(settings.localeIdentifier) {
                settings.localeIdentifier = resolved.normalizedIdentifier
            }
        }
    }
}
