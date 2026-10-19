import Foundation

/// Una release più recente dell'app, con l'unico asset da scaricare. Si salva in `release.json`
/// accanto allo ZIP scaricato, per riproporre l'aggiornamento al riavvio senza rete.
public struct AvailableRelease: Sendable, Equatable, Codable {
    public let version: AppVersion
    /// La pagina della release su GitHub («Novità»).
    public let pageURL: URL
    public let assetName: String
    public let assetURL: URL
    public let size: Int64
    /// Lo SHA-256 dell'asset in esadecimale minuscolo, dal campo `digest` dell'API.
    public let sha256: String

    public init(version: AppVersion, pageURL: URL, assetName: String, assetURL: URL, size: Int64, sha256: String) {
        self.version = version
        self.pageURL = pageURL
        self.assetName = assetName
        self.assetURL = assetURL
        self.size = size
        self.sha256 = sha256
    }

    public var tag: String { version.tag }

    /// Il nome dell'unico asset che il workflow di release pubblica per un tag.
    public static func assetName(for tag: String) -> String {
        "mjm.cleaner-\(tag)-macos-universal.zip"
    }
}

public protocol ReleaseFeed: Sendable {
    /// La release pubblicata più recente se è più recente di `current`, altrimenti `nil`.
    func latestRelease(newerThan current: AppVersion) async throws -> AvailableRelease?
}

/// `GET /repos/markjackmilian/mjm.cleaner/releases/latest`: GitHub esclude da sé bozze e
/// prerelease. Senza autenticazione il limite è di 60 richieste all'ora per indirizzo.
public struct GitHubReleaseFeed: ReleaseFeed {
    public static let latestAddress = "https://api.github.com/repos/markjackmilian/mjm.cleaner/releases/latest"

    private let http: any HTTPClient
    private let userAgent: String

    public init(http: any HTTPClient, currentVersion: AppVersion) {
        self.http = http
        userAgent = "mjm.cleaner/\(currentVersion)"
    }

    public func latestRelease(newerThan current: AppVersion) async throws -> AvailableRelease? {
        guard let url = URL(string: Self.latestAddress) else { throw UpdateError.invalidResponse }
        let response = try await http.get(url, headers: [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": userAgent,
        ])
        guard response.statusCode == 200 else { throw UpdateError.httpStatus(response.statusCode) }
        return try Self.parse(response.body, newerThan: current)
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64
        let digest: String?
    }

    static func parse(_ body: Data, newerThan current: AppVersion) throws -> AvailableRelease? {
        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: body)
        } catch {
            throw UpdateError.invalidResponse
        }
        guard let version = AppVersion(release.tag_name), release.tag_name.hasPrefix("v") else {
            throw UpdateError.invalidRelease(String(localized: "tag «\(release.tag_name)» non nel formato vX.Y.Z", bundle: .module))
        }
        guard version > current else { return nil }

        let expectedName = AvailableRelease.assetName(for: version.tag)
        let matching = release.assets.filter { $0.name.utf8.elementsEqual(expectedName.utf8) }
        guard matching.count == 1, let asset = matching.first else {
            throw UpdateError.invalidRelease(String(localized: "manca l'asset \(expectedName)", bundle: .module))
        }
        guard let assetURL = httpsURL(asset.browser_download_url), let pageURL = httpsURL(release.html_url) else {
            throw UpdateError.invalidRelease(String(localized: "indirizzo non HTTPS", bundle: .module))
        }
        guard asset.size > 0 else {
            throw UpdateError.invalidRelease(String(localized: "asset vuoto", bundle: .module))
        }
        guard let sha256 = sha256Hex(asset.digest) else {
            throw UpdateError.invalidRelease(String(localized: "digest SHA-256 assente", bundle: .module))
        }
        return AvailableRelease(
            version: version, pageURL: pageURL, assetName: expectedName, assetURL: assetURL,
            size: asset.size, sha256: sha256)
    }

    private static func httpsURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host() != nil else { return nil }
        return url
    }

    /// `sha256:` seguito da 64 cifre esadecimali, restituite in minuscolo.
    private static func sha256Hex(_ digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        guard hex.utf8.count == 64, hex.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else {
            return nil
        }
        return hex
    }
}
