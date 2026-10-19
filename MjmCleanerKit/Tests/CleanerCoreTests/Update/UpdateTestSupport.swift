import Foundation
@testable import CleanerCore

/// Le fixture dell'updater, lette dal sorgente dei test come quelle di Docker e Xcode.
enum UpdateFixtures {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }
}

/// Il JSON di `/releases/latest` con i soli campi che l'updater legge.
func releaseJSON(
    tag: String,
    assets: [[String: Any]]? = nil,
    htmlURL: String? = nil
) -> Data {
    let defaultAsset: [String: Any] = [
        "name": "mjm.cleaner-\(tag)-macos-universal.zip",
        "browser_download_url": "https://github.com/markjackmilian/mjm.cleaner/releases/download/\(tag)/mjm.cleaner-\(tag)-macos-universal.zip",
        "size": 3_188_840,
        "digest": "sha256:" + String(repeating: "ab", count: 32),
    ]
    let object: [String: Any] = [
        "tag_name": tag,
        "html_url": htmlURL ?? "https://github.com/markjackmilian/mjm.cleaner/releases/tag/\(tag)",
        "assets": assets ?? [defaultAsset],
    ]
    // Gli oggetti sono costruiti qui sopra: la serializzazione non può fallire.
    return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

func asset(_ name: String, tag: String = "v0.2.0", url: String? = nil, size: Int64 = 10, digest: String? = "sha256:" + String(repeating: "ab", count: 32)) -> [String: Any] {
    var asset: [String: Any] = [
        "name": name,
        "browser_download_url": url ?? "https://github.com/markjackmilian/mjm.cleaner/releases/download/\(tag)/\(name)",
        "size": size,
    ]
    if let digest { asset["digest"] = digest }
    return asset
}

/// Rete finta: risponde a `get` con una risposta fissa e a `download` scrivendo `payload`.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var response: Result<HTTPResponse, any Error>
    private var payload: Data
    private var downloadStatus: Int
    private var failDownloadAfterWriting: (any Error)?
    private(set) var requests: [(URL, [String: String])] = []
    private(set) var downloads: [URL] = []

    init(status: Int = 200, body: Data = Data(), payload: Data = Data(), downloadStatus: Int = 200) {
        response = .success(HTTPResponse(statusCode: status, body: body))
        self.payload = payload
        self.downloadStatus = downloadStatus
    }

    func failGets(with error: any Error) {
        lock.withLock { response = .failure(error) }
    }

    func failDownloads(afterWriting error: any Error) {
        lock.withLock { failDownloadAfterWriting = error }
    }

    var downloadCount: Int { lock.withLock { downloads.count } }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try lock.withLock {
            requests.append((url, headers))
            return try response.get()
        }
    }

    func download(_ url: URL, to destination: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> Int {
        let (payload, status, failure) = lock.withLock { () -> (Data, Int, (any Error)?) in
            downloads.append(url)
            return (self.payload, downloadStatus, failDownloadAfterWriting)
        }
        try payload.write(to: URL(fileURLWithPath: destination))
        progress(Int64(payload.count))
        if let failure { throw failure }
        return status
    }
}
