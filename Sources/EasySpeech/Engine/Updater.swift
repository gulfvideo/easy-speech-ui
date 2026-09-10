import AppKit
import CryptoKit
import Foundation

enum UpdateInstallError: LocalizedError {
    case checksumMismatch(expected: String, actual: String)
    case notWritable(String)
    case mountFailed
    case bundleMissing
    case wrongIdentifier(String)
    case signatureInvalid
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .checksumMismatch(let expected, let actual):
            "The download didn't match the checksum GitHub published, so it was discarded.\n\nExpected \(expected.prefix(16))…\nGot \(actual.prefix(16))…"
        case .notWritable(let path):
            "EasySpeech can't update itself at \(path) because that location isn't writable. Move EasySpeech to your Applications folder and try again."
        case .mountFailed:
            "The downloaded disk image couldn't be opened."
        case .bundleMissing:
            "The disk image didn't contain EasySpeech."
        case .wrongIdentifier(let id):
            "The downloaded app identifies itself as \(id), not EasySpeech. It was discarded."
        case .signatureInvalid:
            "The downloaded app's code signature didn't validate, so it was discarded."
        case .downloadFailed(let detail):
            detail
        }
    }
}

/// Downloads and installs a release, then relaunches.
///
/// **Why this doesn't re-trigger Gatekeeper.** macOS shows the "unidentified developer"
/// prompt for apps carrying `com.apple.quarantine`, which browsers and Mail attach to
/// what they download. `URLSession` doesn't, and this app doesn't opt in via
/// `LSFileQuarantineEnabled`, so an update fetched here arrives unquarantined and the
/// approval the user already granted is never asked for again. The install strips the
/// attribute anyway, in case a future macOS starts adding it.
///
/// Because the app is only ad-hoc signed there's no Developer ID to pin against, so the
/// integrity check is: HTTPS to a hard-coded repository, the SHA-256 GitHub publishes for
/// the asset, a bundle-identifier check, and `codesign` validation of the unpacked app.
/// Any failure discards the download rather than installing it.
enum Updater {

    enum Stage: Sendable, Equatable {
        case downloading
        case verifying
        case installing
        case relaunching
    }

    static func install(
        _ update: AvailableUpdate,
        stage: @MainActor @escaping (Stage) -> Void
    ) async throws {

        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateInstallError.notWritable(parent.path)
        }

        await stage(.downloading)
        let downloaded = try await download(update.downloadURL)
        let workspace = downloaded.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: workspace) }

        await stage(.verifying)
        try verifyChecksum(of: downloaded, expected: update.sha256)
        let staged = try unpackAndValidate(downloaded, into: workspace)

        await stage(.installing)
        // Hand the swap to a detached shell: this process is about to be replaced.
        try scheduleSwapAndRelaunch(staged: staged, destination: destination)

        await stage(.relaunching)
        await MainActor.run { NSApp.terminate(nil) }
    }

    // MARK: - Download

    private static func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("EasySpeech/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("easyspeech-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        do {
            let (temporary, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateInstallError.downloadFailed("The download failed with HTTP \(http.statusCode).")
            }
            let target = workspace.appendingPathComponent("update.dmg")
            try FileManager.default.moveItem(at: temporary, to: target)
            return target
        } catch let error as UpdateInstallError {
            throw error
        } catch {
            throw UpdateInstallError.downloadFailed(error.localizedDescription)
        }
    }

    // MARK: - Verification

    private static func verifyChecksum(of file: URL, expected: String) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()

        guard actual == expected.lowercased() else {
            throw UpdateInstallError.checksumMismatch(expected: expected, actual: actual)
        }
    }

    /// Mounts the image, copies the app out, and checks it really is EasySpeech.
    private static func unpackAndValidate(_ image: URL, into workspace: URL) throws -> URL {
        guard let mountPoint = mount(image) else { throw UpdateInstallError.mountFailed }
        defer { detach(mountPoint) }

        let source = mountPoint.appendingPathComponent("EasySpeech.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw UpdateInstallError.bundleMissing
        }

        let staged = workspace.appendingPathComponent("EasySpeech.app")
        // ditto preserves the bundle's extended attributes and signature; cp does not.
        guard run("/usr/bin/ditto", [source.path, staged.path]).status == 0 else {
            throw UpdateInstallError.bundleMissing
        }

        guard let bundle = Bundle(url: staged),
              let identifier = bundle.bundleIdentifier else {
            throw UpdateInstallError.bundleMissing
        }
        guard identifier == Bundle.main.bundleIdentifier else {
            throw UpdateInstallError.wrongIdentifier(identifier)
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", staged.path]).status == 0 else {
            throw UpdateInstallError.signatureInvalid
        }

        // Belt and braces: nothing should have attached this, but make sure.
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    // MARK: - Swap

    /// Waits for this process to exit, swaps the bundle, and reopens the app.
    /// Kept inline rather than written to a script file so there's no window in which
    /// something else could rewrite it before it runs.
    private static func scheduleSwapAndRelaunch(staged: URL, destination: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let new = destination.path + ".new"
        let old = destination.path + ".old"

        let script = """
        for _ in $(seq 1 150); do
          /bin/kill -0 \(pid) 2>/dev/null || break
          /bin/sleep 0.2
        done
        /bin/rm -rf \(quote(new)) \(quote(old)) || exit 1
        /usr/bin/ditto \(quote(staged.path)) \(quote(new)) || exit 1
        /bin/mv \(quote(destination.path)) \(quote(old)) || exit 1
        if ! /bin/mv \(quote(new)) \(quote(destination.path)); then
          /bin/mv \(quote(old)) \(quote(destination.path))
          exit 1
        fi
        /bin/rm -rf \(quote(old))
        /usr/bin/xattr -dr com.apple.quarantine \(quote(destination.path)) 2>/dev/null
        /usr/bin/open -n \(quote(destination.path))
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        // Survive this app's termination.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    // MARK: - Shell helpers

    private static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func mount(_ image: URL) -> URL? {
        let result = run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", image.path])
        guard result.status == 0 else { return nil }
        for line in result.output.components(separatedBy: .newlines).reversed() {
            if let range = line.range(of: "/Volumes/") {
                return URL(fileURLWithPath: String(line[range.lowerBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    private static func detach(_ mountPoint: URL) {
        _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
