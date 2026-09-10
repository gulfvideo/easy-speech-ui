import Foundation

/// Watches a folder and reports media files that appear in it.
///
/// Aimed at recurring work — a podcast archiver dropping this week's episode, a recorder
/// syncing to a folder — so the transcription happens without anyone opening the app.
///
/// Two things make this less trivial than it looks. A file appears the moment copying
/// *starts*, so it's only offered once its size has stopped changing. And the app writes
/// its own `.txt`/`.srt` output beside the source, so anything that isn't decodable media
/// is ignored outright and every path is remembered to avoid a loop.
@MainActor
final class FolderWatcher {

    /// How long a file's size must hold steady before it counts as finished copying.
    private static let quietPeriod: TimeInterval = 2.0
    private static let pollInterval: TimeInterval = 2.0

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var timer: Timer?
    private var url: URL?

    /// Paths already offered, so a folder that keeps its files doesn't re-queue them.
    private var handled: Set<String> = []
    /// Size and timestamp of files still settling.
    private var pending: [String: (size: Int, seenAt: Date)] = [:]

    private let onFilesReady: ([URL]) -> Void

    /// Set when the folder can't be read. macOS gates Desktop, Documents, Downloads and
    /// iCloud Drive behind TCC, and a denied read looks exactly like an empty folder — so
    /// an unattended feature would sit there doing nothing with no explanation.
    private(set) var accessProblem: String?

    init(onFilesReady: @escaping ([URL]) -> Void) {
        self.onFilesReady = onFilesReady
    }

    // No deinit teardown: Timer isn't Sendable so a nonisolated deinit can't touch it.
    // The watcher is owned for the app's lifetime and `stop()` does the cleanup whenever
    // the setting changes.

    var watchedURL: URL? { url }

    func start(watching folder: URL) {
        stop()
        url = folder

        guard canRead(folder) else {
            accessProblem = "EasySpeech can't read \(folder.lastPathComponent). macOS protects Desktop, Documents, Downloads and iCloud Drive — grant access in System Settings › Privacy & Security › Files and Folders, or choose a folder elsewhere."
            return
        }
        accessProblem = nil

        // Everything already there is treated as seen: switching this on shouldn't
        // suddenly transcribe a folder's entire backlog.
        handled = Set(mediaFiles(in: folder).map(\.path))

        descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { url = nil; return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend], queue: .main)
        source.setEventHandler { [weak self] in self?.scan() }
        source.setCancelHandler { [weak self] in
            guard let self, descriptor >= 0 else { return }
            close(descriptor)
            self.descriptor = -1
        }
        source.resume()
        self.source = source

        // FSEvents can miss writes from other volumes, so poll gently as a backstop and
        // to re-check files that are still being copied.
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            MainActor.assumeIsolated { self.scan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        source?.cancel()
        source = nil
        timer?.invalidate()
        timer = nil
        url = nil
        accessProblem = nil
        pending.removeAll()
        handled.removeAll()
    }

    /// A TCC denial surfaces as a throwing directory read, not as a permissions API.
    private func canRead(_ folder: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }

    // MARK: - Scanning

    private func scan() {
        guard let folder = url else { return }
        var ready: [URL] = []

        for file in mediaFiles(in: folder) where !handled.contains(file.path) {
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? nil
            guard let size else { continue }

            if let seen = pending[file.path], seen.size == size {
                if Date().timeIntervalSince(seen.seenAt) >= Self.quietPeriod {
                    pending.removeValue(forKey: file.path)
                    handled.insert(file.path)
                    ready.append(file)
                }
            } else {
                // New, or still growing — restart its clock.
                pending[file.path] = (size, Date())
            }
        }

        if !ready.isEmpty { onFilesReady(ready) }
    }

    private func mediaFiles(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])) ?? []

        return contents.filter { file in
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return false
            }
            // Transcripts this app writes are not media, so they can't cause a loop.
            return AudioSource.supportedExtensions.contains(file.pathExtension.lowercased())
        }
    }
}
