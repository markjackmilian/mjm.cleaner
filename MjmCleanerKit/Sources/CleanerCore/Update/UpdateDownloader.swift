import CryptoKit
import Foundation

/// Uno ZIP scaricato il cui SHA-256 coincide con il digest pubblicato.
public struct DownloadedUpdate: Sendable, Equatable {
    public let release: AvailableRelease
    /// `<updates>/<tag>/`: tutto ciò che riguarda questa release.
    public let directory: String
    public let zipPath: String

    public init(release: AvailableRelease, directory: String, zipPath: String) {
        self.release = release
        self.directory = directory
        self.zipPath = zipPath
    }
}

/// Scarica l'asset in `<updates>/<tag>/`, lo accetta solo se lo SHA-256 coincide con il digest e
/// tiene una sola release in cache. Lavora sul disco vero con `FileManager`: la cartella è
/// dell'app (Application Support, protetta dalla deny-list) e serve rinominare, cosa che il
/// protocollo `FileSystem` del Core non offre.
public struct UpdateDownloader: Sendable {
    static let partialName = "download.partial"
    static let releaseFileName = "release.json"

    private let http: any HTTPClient
    private let updatesDirectory: String

    public init(http: any HTTPClient, updatesDirectory: String) {
        self.http = http
        self.updatesDirectory = updatesDirectory
    }

    /// `progress` riceve la frazione scaricata, fra 0 e 1.
    public func download(_ release: AvailableRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> DownloadedUpdate {
        removeTagDirectories(keeping: release.tag)
        let directory = PathText.join(updatesDirectory, release.tag)
        let zipPath = PathText.join(directory, release.assetName)
        let partial = PathText.join(directory, Self.partialName)
        let manager = FileManager.default
        try manager.createDirectory(atPath: directory, withIntermediateDirectories: true)

        if manager.fileExists(atPath: zipPath), (try? Self.sha256(of: zipPath)) == release.sha256 {
            try writeRelease(release, in: directory)
            progress(1)
            return DownloadedUpdate(release: release, directory: directory, zipPath: zipPath)
        }
        try? manager.removeItem(atPath: zipPath)
        try? manager.removeItem(atPath: partial)

        let total = Double(max(release.size, 1))
        do {
            let status = try await http.download(release.assetURL, to: partial) { written in
                progress(min(Double(written) / total, 1))
            }
            guard status == 200 else { throw UpdateError.httpStatus(status) }
            guard try Self.sha256(of: partial) == release.sha256 else { throw UpdateError.digestMismatch }
            try manager.moveItem(atPath: partial, toPath: zipPath)
            try writeRelease(release, in: directory)
        } catch {
            try? manager.removeItem(atPath: partial)
            try? manager.removeItem(atPath: zipPath)
            throw error
        }
        return DownloadedUpdate(release: release, directory: directory, zipPath: zipPath)
    }

    /// Lo ZIP già scaricato di una release più recente di `current`, se `release.json` è leggibile
    /// e il digest coincide ancora. Le cartelle di ogni altra release si cancellano.
    public func cached(newerThan current: AppVersion) -> DownloadedUpdate? {
        let manager = FileManager.default
        var best: DownloadedUpdate?
        for tag in tagDirectories() {
            let directory = PathText.join(updatesDirectory, tag)
            guard let data = manager.contents(atPath: PathText.join(directory, Self.releaseFileName)),
                  let release = try? JSONDecoder().decode(AvailableRelease.self, from: data),
                  release.tag == tag, release.version > current,
                  release.assetName == AvailableRelease.assetName(for: tag) else { continue }
            let zipPath = PathText.join(directory, release.assetName)
            guard (try? Self.sha256(of: zipPath)) == release.sha256 else { continue }
            if best.map({ release.version > $0.release.version }) ?? true {
                best = DownloadedUpdate(release: release, directory: directory, zipPath: zipPath)
            }
        }
        removeTagDirectories(keeping: best?.release.tag)
        return best
    }

    /// Cancella le cartelle di tutte le release tranne `tag`; i file come `install-result` restano.
    public func removeTagDirectories(keeping tag: String?) {
        for other in tagDirectories() where other != tag {
            try? FileManager.default.removeItem(atPath: PathText.join(updatesDirectory, other))
        }
    }

    /// Le sottocartelle il cui nome è un tag `vX.Y.Z`: solo quelle sono dell'updater.
    private func tagDirectories() -> [String] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: updatesDirectory)) ?? []
        return names.sorted().filter { name in
            var isDirectory: ObjCBool = false
            return name.hasPrefix("v") && AppVersion(name) != nil
                && manager.fileExists(atPath: PathText.join(updatesDirectory, name), isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private func writeRelease(_ release: AvailableRelease, in directory: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(release).write(to: URL(fileURLWithPath: PathText.join(directory, Self.releaseFileName)), options: .atomic)
    }

    /// SHA-256 in esadecimale minuscolo, letto a blocchi da 1 MB.
    public static func sha256(of path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
