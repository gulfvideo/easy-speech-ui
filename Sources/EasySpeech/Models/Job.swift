import Foundation

/// Lifecycle of one queued file.
enum JobState: Equatable, Sendable {
    case queued
    case preparing
    case transcribing(progress: Double)
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
        case .transcribing(let p): "Transcribing \(Int(p * 100))%"
        case .translating: "Translating"
        case .writing: "Writing"
        case .finished: "Done"
        case .failed(let m): "Failed — \(m)"
        case .cancelled: "Cancelled"
        }
    }

    var fractionComplete: Double? {
        switch self {
        case .queued: 0
        case .preparing: 0.02
        case .transcribing(let p): max(0.02, p)
        case .translating: 0.9
        case .writing: 0.97
        case .finished: 1
        default: nil
        }
    }
}

@MainActor
@Observable
final class Job: Identifiable {
    let id = UUID()
    let url: URL
    var state: JobState = .queued
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
