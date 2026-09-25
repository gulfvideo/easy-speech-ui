import AppKit
import Foundation
import Observation

/// Batch queue, running `AppSettings.concurrentJobs` files at a time.
///
/// A single transcription does not saturate the Neural Engine, so running several at once
/// raises throughput even though each individual file slows down. Measured on an M5 Pro over
/// 30-minute files: 72x realtime at 1, 207x at 4, 255x at 6, falling back to 248x at 8. The
/// setting is capped at 6 because that is where the curve turns over.
@MainActor
@Observable
final class JobQueue {

    var jobs: [Job] = []
    private(set) var isProcessing = false
    /// Paused means "start nothing new". Files already transcribing run to the end, because
    /// SpeechAnalyzer has no way to suspend a stream — stopping one would throw the work away.
    private(set) var isPaused = false
    private(set) var modelDownload: Progress?

    private var worker: Task<Void, Never>?
    private var watcher: FolderWatcher?
    private let settings = AppSettings.shared

    var pendingCount: Int { jobs.filter { !$0.state.isTerminal }.count }
    /// True while any file is still waiting to start.
    var hasQueuedWork: Bool { jobs.contains { if case .queued = $0.state { true } else { false } } }

    /// How many files the last add dropped because their output already existed.
    private(set) var lastSkippedCount = 0
    var activeJob: Job? { jobs.first { $0.state.isActive } }

    /// Starts, stops or re-points the watched folder to match the current settings.
    func syncFolderWatch() {
        guard let folder = settings.watchFolderURL else {
            watcher?.stop()
            watcher = nil
            return
        }
        if watcher?.watchedURL == folder { return }

        let watcher = self.watcher ?? FolderWatcher { [weak self] urls in
            self?.add(urls)
        }
        self.watcher = watcher
        watcher.start(watching: folder)
    }

    /// Non-nil when the watched folder can't be read, so the UI can say why.
    var watchProblem: String? { watcher?.accessProblem }

    // MARK: - Queue management

    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let existing = Set(jobs.map(\.url))
        let supported = urls
            .filter { !existing.contains($0) }
            .filter { AudioSource.supportedExtensions.contains($0.pathExtension.lowercased()) }

        let fresh = supported.filter { !alreadyTranscribed($0) }
        lastSkippedCount = supported.count - fresh.count

        jobs.append(contentsOf: fresh.map(Job.init(url:)))
        if !fresh.isEmpty { startIfIdle() }
        return fresh.count
    }

    func remove(_ job: Job) {
        guard !job.state.isActive else { return }
        jobs.removeAll { $0.id == job.id }
    }

    /// Moves a queued job in front of everything else still waiting.
    ///
    /// Only reorders the waiting tail: files already transcribing keep going, and the job
    /// lands after them rather than at index 0, so the list still reads top to bottom in
    /// the order work actually happens.
    func moveToTopOfQueue(_ job: Job) {
        guard case .queued = job.state else { return }
        guard let from = jobs.firstIndex(where: { $0.id == job.id }) else { return }

        let insertAt = jobs.firstIndex { if case .queued = $0.state { true } else { false } }
        guard let insertAt, insertAt != from else { return }

        jobs.remove(at: from)
        jobs.insert(job, at: insertAt)
    }

    /// True when there is anything ahead of this job that it could jump.
    func canMoveToTopOfQueue(_ job: Job) -> Bool {
        guard case .queued = job.state else { return false }
        guard let first = jobs.firstIndex(where: { if case .queued = $0.state { true } else { false } }),
              let mine = jobs.firstIndex(where: { $0.id == job.id })
        else { return false }
        return mine > first
    }

    func clearFinished() {
        jobs.removeAll { $0.state.isTerminal }
    }

    func retry(_ job: Job) {
        guard job.state.isTerminal else { return }
        job.state = .queued
        job.progress = 0
        job.outputs = []
        job.transcript = Transcript()
        startIfIdle()
    }

    func startIfIdle() {
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    /// Stops taking new files. Anything mid-flight finishes and is written out.
    func pause() {
        guard isProcessing, !isPaused else { return }
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        // Covers the case where the drain did finish — e.g. paused after the last file.
        startIfIdle()
    }

    func cancelAll() {
        worker?.cancel()
        worker = nil
        isPaused = false
        isProcessing = false
        modelDownload = nil
        for job in jobs where !job.state.isTerminal {
            job.state = .cancelled
        }
    }

    /// True when every file this run would write already exists in the destination.
    ///
    /// Checked against the destination rather than the source folder, so a custom output
    /// folder is honoured. Deliberately requires *all* enabled formats to be present: turning
    /// on .srt later should re-run files that only have a .txt, not skip them.
    private func alreadyTranscribed(_ url: URL) -> Bool {
        guard settings.skipAlreadyTranscribed, settings.writesAnyFile else { return false }

        return Self.hasAllOutputs(folder: settings.outputFolder(for: url),
                                  base: url.deletingPathExtension().lastPathComponent,
                                  extensions: settings.enabledOutputExtensions)
    }

    /// True when every one of `extensions` already exists beside `base` in `folder`.
    ///
    /// Shared with the command line tool so the two cannot drift apart — they answer the same
    /// question and previously each had their own copy of the answer.
    nonisolated static func hasAllOutputs(folder: URL, base: String, extensions: [String]) -> Bool {
        guard !extensions.isEmpty else { return false }
        return extensions.allSatisfy { ext in
            FileManager.default.fileExists(
                atPath: folder.appendingPathComponent(base).appendingPathExtension(ext).path
            )
        }
    }

    // MARK: - Processing

    private func drain() async {
        isProcessing = true
        defer {
            isProcessing = false
            modelDownload = nil
            worker = nil
        }

        // Read once: changing the setting mid-run applies to the next run, not this one.
        let limit = AppSettings.clampConcurrency(settings.concurrentJobs)

        await withTaskGroup(of: Void.self) { group in
            var running = 0
            while !Task.isCancelled {
                // Wait for a free slot *before* claiming. Claiming first would mark a
                // seventh file active while it sat waiting, and would let one more start
                // after a pause.
                if running >= limit {
                    await group.next()
                    running -= 1
                }
                guard let job = claimNextQueued() else {
                    // Paused: keep this drain alive rather than letting it finish, so Resume
                    // picks straight back up instead of racing the wind-down.
                    if isPaused, hasQueuedWork {
                        try? await Task.sleep(for: .milliseconds(200))
                        continue
                    }
                    break
                }
                group.addTask { await self.process(job) }
                running += 1
            }
            await group.waitForAll()
        }
    }

    /// Takes the next queued job and marks it claimed in the same main-actor step, so two
    /// workers can never pull the same file.
    private func claimNextQueued() -> Job? {
        guard !isPaused else { return nil }
        guard let job = jobs.first(where: { if case .queued = $0.state { true } else { false } })
        else { return nil }
        job.state = .preparing
        return job
    }

    private func process(_ job: Job) async {
        job.state = .preparing
        job.startedAt = Date()
        job.finishedAt = nil

        do {
            job.duration = try? await AudioSource.duration(of: job.url)

            let options = FileTranscriber.Options(
                locale: settings.locale,
                censorProfanity: settings.censorProfanity,
                vocabulary: settings.vocabulary,
                corrections: settings.corrections
            )

            var transcript = try await FileTranscriber.transcribe(url: job.url, options: options) { stage in
                Task { @MainActor in
                    switch stage {
                    case .preparing:
                        job.state = .preparing
                    case .downloadingModel(let progress):
                        self.modelDownload = progress
                        job.state = .preparing
                    case .transcribing(let fraction):
                        self.modelDownload = nil
                        job.progress = fraction
                        // Assigning an unchanged enum still notifies observers, so only
                        // transition when it is actually a transition.
                        if job.state != .transcribing { job.state = .transcribing }
                    }
                }
            }

            try Task.checkCancellation()

            if settings.translate {
                job.state = .translating
                let target = Locale.Language(identifier: settings.translationTarget)
                transcript = try await TranslationService.translate(transcript, to: target)
            }

            job.transcript = transcript

            if settings.writesAnyFile {
                job.state = .writing
                job.outputs = try writeOutputs(for: job, transcript: transcript)
            }

            job.state = .finished
            job.finishedAt = Date()
            revealOrOpenIfRequested(job)

        } catch is CancellationError {
            job.state = .cancelled
            job.finishedAt = Date()
        } catch {
            job.state = .failed(error.localizedDescription)
            job.finishedAt = Date()
        }
    }

    // MARK: - Writing files

    private func writeOutputs(for job: Job, transcript: Transcript) throws -> [URL] {
        let folder = settings.customOutputURL ?? job.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let base = job.url.deletingPathExtension().lastPathComponent
        var written: [URL] = []

        func write(_ contents: String, extension ext: String) throws {
            // Only write what's missing, so enabling a new format for a folder that's already
            // been transcribed adds that format instead of duplicating the others.
            let existing = folder.appendingPathComponent(base).appendingPathExtension(ext)
            if settings.skipAlreadyTranscribed, FileManager.default.fileExists(atPath: existing.path) {
                written.append(existing)
                return
            }
            let target = Self.nonClobberingURL(folder: folder, base: base, ext: ext)
            try contents.write(to: target, atomically: true, encoding: .utf8)
            written.append(target)
        }

        if settings.writeText {
            try write(SubtitleWriter.text(for: transcript, timestamps: settings.timestampsInText), extension: "txt")
        }
        if settings.writeSRT {
            try write(SubtitleWriter.srt(for: transcript), extension: "srt")
        }
        if settings.writeVTT {
            try write(SubtitleWriter.vtt(for: transcript), extension: "vtt")
        }
        return written
    }

    /// Never overwrites an existing file — appends " 2", " 3" the way the Finder does.
    /// Nonisolated so the command line tool can use it without a main actor.
    nonisolated static func nonClobberingURL(folder: URL, base: String, ext: String) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    private func revealOrOpenIfRequested(_ job: Job) {
        guard let first = job.outputs.first else { return }
        if settings.openWhenDone {
            NSWorkspace.shared.open(first)
        } else if settings.revealWhenDone {
            NSWorkspace.shared.activateFileViewerSelecting(job.outputs)
        }
    }
}
