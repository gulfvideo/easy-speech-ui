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
    private(set) var modelDownload: Progress?

    private var worker: Task<Void, Never>?
    private var watcher: FolderWatcher?
    private let settings = AppSettings.shared

    var pendingCount: Int { jobs.filter { !$0.state.isTerminal }.count }
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

    func clearFinished() {
        jobs.removeAll { $0.state.isTerminal }
    }

    func retry(_ job: Job) {
        guard job.state.isTerminal else { return }
        job.state = .queued
        job.outputs = []
        job.transcript = Transcript()
        startIfIdle()
    }

    func startIfIdle() {
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    func cancelAll() {
        worker?.cancel()
        worker = nil
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

        let extensions = settings.enabledOutputExtensions
        guard !extensions.isEmpty else { return false }

        let folder = settings.outputFolder(for: url)
        let base = url.deletingPathExtension().lastPathComponent

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
            while let job = claimNextQueued() {
                if Task.isCancelled {
                    job.state = .cancelled
                    break
                }
                if running >= limit {
                    await group.next()
                    running -= 1
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
                        job.state = .transcribing(progress: fraction)
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
