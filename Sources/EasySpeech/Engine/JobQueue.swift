import AppKit
import Foundation
import Observation

/// Sequential batch queue, mirroring EasyWhisperUI's one-at-a-time behaviour.
///
/// Files are processed in order because the Neural Engine is the bottleneck — running
/// several at once makes every file slower rather than the batch faster.
@MainActor
@Observable
final class JobQueue {

    var jobs: [Job] = []
    private(set) var isProcessing = false
    private(set) var modelDownload: Progress?

    private var worker: Task<Void, Never>?
    private let settings = AppSettings.shared

    var pendingCount: Int { jobs.filter { !$0.state.isTerminal }.count }
    var activeJob: Job? { jobs.first { $0.state.isActive } }

    // MARK: - Queue management

    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let existing = Set(jobs.map(\.url))
        let fresh = urls
            .filter { !existing.contains($0) }
            .filter { AudioSource.allExtensions.contains($0.pathExtension.lowercased()) }

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

    // MARK: - Processing

    private func drain() async {
        isProcessing = true
        defer {
            isProcessing = false
            modelDownload = nil
            worker = nil
        }

        while let job = jobs.first(where: { if case .queued = $0.state { true } else { false } }) {
            if Task.isCancelled {
                job.state = .cancelled
                return
            }
            await process(job)
        }
    }

    private func process(_ job: Job) async {
        job.state = .preparing
        job.startedAt = Date()
        job.finishedAt = nil

        do {
            job.duration = try? await AudioSource.duration(of: job.url)

            let options = FileTranscriber.Options(
                locale: settings.locale,
                censorProfanity: settings.censorProfanity
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
    static func nonClobberingURL(folder: URL, base: String, ext: String) -> URL {
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
