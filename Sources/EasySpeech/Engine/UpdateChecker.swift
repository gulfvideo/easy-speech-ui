import Foundation

/// A published release newer than the running build.
struct AvailableUpdate: Sendable, Equatable, Identifiable {
    var id: String { tag }
    let version: String
    let tag: String
    let notes: String
    let downloadURL: URL
    /// Hex SHA-256 the download must match. Never nil — an unverifiable asset is refused.
    let sha256: String
    let byteCount: Int
    let releasePage: URL
}

enum UpdateCheckError: LocalizedError {
    case network(String)
    case noAsset
    case noChecksum
    case badResponse

    var errorDescription: String? {
        switch self {
        case .network(let detail): detail
        case .noAsset: "That release has no macOS download."
        case .noChecksum: "That release doesn't publish a checksum, so it can't be verified. Download it manually from the releases page."
        case .badResponse: "GitHub returned something unexpected."
        }
    }
}

/// Looks for newer releases on GitHub.
///
/// The repository is hard-coded rather than configurable: an updater that can be pointed
/// at an arbitrary host by a preference is a way to get arbitrary code onto the machine.
enum UpdateChecker {

    static let repository = "gulfvideo/easy-speech-ui"
    static var releasesPage: URL { URL(string: "https://github.com/\(repository)/releases")! }

    private static var latestEndpoint: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Returns the release only when it's newer than what's running.
    static func check() async throws -> AvailableUpdate? {
        var request = URLRequest(url: latestEndpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EasySpeech/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateCheckError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.badResponse }
        // 404 simply means no releases have been published yet.
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else {
            throw UpdateCheckError.network("GitHub returned HTTP \(http.statusCode).")
        }

        let payload: GitHubRelease
        do {
            payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateCheckError.badResponse
        }

        let version = payload.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard isNewer(version, than: currentVersion) else { return nil }

        guard let asset = payload.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let url = URL(string: asset.browserDownloadURL),
              url.scheme == "https", url.host?.hasSuffix("github.com") == true else {
            throw UpdateCheckError.noAsset
        }

        // Prefer GitHub's own digest; fall back to a checksum published in the notes.
        guard let checksum = asset.sha256Digest ?? firstSHA256(in: payload.body ?? "") else {
            throw UpdateCheckError.noChecksum
        }

        return AvailableUpdate(
            version: version,
            tag: payload.tagName,
            notes: payload.body ?? "",
            downloadURL: url,
            sha256: checksum.lowercased(),
            byteCount: asset.size,
            releasePage: URL(string: payload.htmlURL) ?? releasesPage
        )
    }

    /// Numeric component-wise comparison, so 1.10.0 correctly beats 1.9.0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(whereSeparator: { $0 == "." || $0 == "-" })
            .compactMap { Int($0.prefix(while: \.isNumber)) }
    }

    private static func firstSHA256(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b[0-9a-fA-F]{64}\\b"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Wire format

    private struct GitHubRelease: Decodable {
        let tagName: String
        let body: String?
        let htmlURL: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let size: Int
        let browserDownloadURL: String
        /// GitHub reports this as "sha256:<hex>".
        let digest: String?

        var sha256Digest: String? {
            guard let digest, digest.hasPrefix("sha256:") else { return nil }
            return String(digest.dropFirst("sha256:".count))
        }

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }
}
