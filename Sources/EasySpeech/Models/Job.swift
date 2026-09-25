import Foundation

/// Lifecycle of one queued file.
enum JobState: Equatable, Sendable {
    case queued
    case preparing
    case transcribing
    case translating
    case writing
    case finished
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .preparing, .transcribing, .translating, .writing: true
        default: false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .finished, .failed, .cancelled: true
        default: false
        }
    }

    var label: String {
        switch self {
        case .queued: "Queued"
        case .preparing: "Preparing"
        case .transcribing: "Transcribing"
        case .translating: "Translating"
        case .writing: "Writing"
        case .finished: "Done"
        case .failed(let m): "Failed — \(m)"
        case .cancelled: "Cancelled"
        }
    }

}

@MainActor
@Observable
final class Job: Identifiable {
    let id = UUID()
    let url: URL
    var state: JobState = .queued
    /// Kept out of `state` deliberately.
    ///
    /// Progress ticks a few hundred times per file. While it lived inside
    /// `.transcribing(progress:)`, every tick mutated `state`, and anything that *scans* states
    /// — `pendingCount`, `activeJob`, the window subtitle — is read by `ContentView.body`. So a
    /// single tick invalidated the whole split view and forced SwiftUI to re-diff every row in
    /// the file list. Sampling showed 89% of main-thread time inside `OutlineListCoordinator`
    /// re-diffing rows, and it scaled with both the number of files and the concurrency.
    ///
    /// As a separate property only `JobRow` reads it, so a tick repaints one row. `state` now
    /// changes about four times per file instead of a few hundred.
    var progress: Double = 0
    var transcript = Transcript()
    /// Files written to disk for this job, shown in the UI and revealable in the Finder.
    var outputs: [URL] = []
    var duration: TimeInterval?
    var startedAt: Date?
    var finishedAt: Date?

    init(url: URL) {
        self.url = url
    }

    var displayName: String { url.lastPathComponent }

    /// What to show a human. Combines `state` with `progress` so the percentage survives
    /// having been moved out of the enum — read this from detail views, never from anything
    /// that renders once per row.
    var statusText: String {
        if case .transcribing = state { return "Transcribing \(Int(progress * 100))%" }
        return state.label
    }

    var elapsed: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    /// Realtime factor: how many seconds of audio processed per second of wall clock.
    var speedFactor: Double? {
        guard let duration, let elapsed, elapsed > 0.01, duration > 0 else { return nil }
        return duration / elapsed
    }
}
