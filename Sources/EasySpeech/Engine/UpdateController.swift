import Foundation
import Observation

/// Drives update checks and installs, and holds the state the UI reflects.
@MainActor
@Observable
final class UpdateController {

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate)
        case installing(Updater.Stage)
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Set when a background check finds something, so the UI can raise the sheet once.
    var pendingPrompt: AvailableUpdate?

    private let settings = AppSettings.shared
    private var inFlight: Task<Void, Never>?

    var currentVersion: String { UpdateChecker.currentVersion }

    var isBusy: Bool {
        switch state {
        case .checking, .installing: true
        default: false
        }
    }

    /// Runs at launch. Quiet: never reports "up to date" or network trouble, because the
    /// user didn't ask. Only a genuine update surfaces.
    func checkInBackground() {
        guard settings.automaticUpdateChecks else { return }
        // Once a day is plenty for an app like this.
        if let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < 86_400 { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard !isBusy else { return }
        inFlight?.cancel()
        if userInitiated { state = .checking }

        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                let update = try await UpdateChecker.check()
                settings.lastUpdateCheck = Date()

                if let update {
                    state = .available(update)
                    pendingPrompt = update
                } else if userInitiated {
                    state = .upToDate
                } else {
                    state = .idle
                }
            } catch {
                // A failed background check is not the user's problem.
                state = userInitiated ? .failed(error.localizedDescription) : .idle
            }
        }
    }

    func install(_ update: AvailableUpdate) {
        guard !isBusy else { return }
        state = .installing(.downloading)

        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                try await Updater.install(update) { stage in
                    self.state = .installing(stage)
                }
                // On success the app is terminating; nothing more to do.
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func dismiss() {
        pendingPrompt = nil
        if case .available = state { state = .idle }
        if case .failed = state { state = .idle }
        if case .upToDate = state { state = .idle }
    }
}
