import CryptoKit
import Foundation
import Testing
@testable import CleanerCore

struct UpdateDownloaderTests {
    private static let payload = Data("contenuto dello zip".utf8)
    private static let payloadDigest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

    private static func release(_ tag: String = "v0.2.0", sha256: String = payloadDigest) throws -> AvailableRelease {
        let version = try #require(AppVersion(tag))
        let name = AvailableRelease.assetName(for: tag)
        return AvailableRelease(
            version: version,
            pageURL: try #require(URL(string: "https://github.com/markjackmilian/mjm.cleaner/releases/tag/\(tag)")),
            assetName: name,
            assetURL: try #require(URL(string: "https://github.com/markjackmilian/mjm.cleaner/releases/download/\(tag)/\(name)")),
            size: Int64(payload.count),
            sha256: sha256)
    }

    private static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    @Test func hashesFilesAsLowercaseHex() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = try temp.file("a.zip", contents: "contenuto dello zip")
        #expect(try UpdateDownloader.sha256(of: file) == Self.payloadDigest)
    }

    @Test func keepsTheZipAndItsReleaseWhenTheDigestMatches() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let release = try Self.release()
        let progress = Recorder<Double>()
        let downloaded = try await UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path)
            .download(release) { progress.append($0) }

        #expect(downloaded.directory == temp.path + "/v0.2.0")
        #expect(downloaded.zipPath == temp.path + "/v0.2.0/mjm.cleaner-v0.2.0-macos-universal.zip")
        #expect(try Data(contentsOf: URL(fileURLWithPath: downloaded.zipPath)) == Self.payload)
        #expect(!Self.exists(temp.path + "/v0.2.0/download.partial"))
        let saved = try JSONDecoder().decode(AvailableRelease.self, from: Data(contentsOf: URL(fileURLWithPath: temp.path + "/v0.2.0/release.json")))
        #expect(saved == release)
        #expect(progress.values.last == 1)
    }

    @Test func wrongDigestDeletesTheDownload() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let release = try Self.release(sha256: String(repeating: "0", count: 64))
        await #expect(throws: UpdateError.digestMismatch) {
            try await UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path).download(release) { _ in }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.path + "/v0.2.0").isEmpty)
    }

    @Test func nonOKStatusDeletesThePartialFile() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        await #expect(throws: UpdateError.httpStatus(404)) {
            try await UpdateDownloader(http: FakeHTTP(payload: Self.payload, downloadStatus: 404), updatesDirectory: temp.path)
                .download(try Self.release()) { _ in }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.path + "/v0.2.0").isEmpty)
    }

    @Test func interruptedDownloadDeletesThePartialFile() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let http = FakeHTTP(payload: Self.payload)
        http.failDownloads(afterWriting: CocoaError(.fileWriteOutOfSpace))
        await #expect(throws: CocoaError.self) {
            try await UpdateDownloader(http: http, updatesDirectory: temp.path).download(try Self.release()) { _ in }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.path + "/v0.2.0").isEmpty)
    }

    @Test func verifiedZipAlreadyOnDiskIsNotDownloadedAgain() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let http = FakeHTTP(payload: Self.payload)
        let downloader = UpdateDownloader(http: http, updatesDirectory: temp.path)
        _ = try await downloader.download(try Self.release()) { _ in }
        _ = try await downloader.download(try Self.release()) { _ in }
        #expect(http.downloadCount == 1)
    }

    @Test func corruptedZipOnDiskIsDownloadedAgain() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.file("v0.2.0/mjm.cleaner-v0.2.0-macos-universal.zip", contents: "alterato")
        let http = FakeHTTP(payload: Self.payload)
        let downloaded = try await UpdateDownloader(http: http, updatesDirectory: temp.path).download(try Self.release()) { _ in }
        #expect(http.downloadCount == 1)
        #expect(try UpdateDownloader.sha256(of: downloaded.zipPath) == Self.payloadDigest)
    }

    @Test func downloadingARemovesOtherReleasesButKeepsInstallFiles() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.file("v0.1.5/mjm.cleaner-v0.1.5-macos-universal.zip", contents: "vecchio")
        try temp.file("install-result", contents: "ok v0.1.5")
        try temp.directory("non-un-tag")
        _ = try await UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path).download(try Self.release()) { _ in }
        #expect(!Self.exists(temp.path + "/v0.1.5"))
        #expect(Self.exists(temp.path + "/install-result"))
        #expect(Self.exists(temp.path + "/non-un-tag"))
    }

    @Test func cachedReturnsTheVerifiedNewerDownload() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let downloader = UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path)
        let downloaded = try await downloader.download(try Self.release()) { _ in }
        #expect(downloader.cached(newerThan: AppVersion(major: 0, minor: 1, patch: 0)) == downloaded)
    }

    @Test func cachedDropsReleasesThatAreNoLongerNewer() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let downloader = UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path)
        _ = try await downloader.download(try Self.release()) { _ in }
        #expect(downloader.cached(newerThan: AppVersion(major: 0, minor: 2, patch: 0)) == nil)
        #expect(!Self.exists(temp.path + "/v0.2.0"))
    }

    @Test func cachedDropsAZipAlteredAfterTheDownload() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let downloader = UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path)
        let downloaded = try await downloader.download(try Self.release()) { _ in }
        try Data("alterato".utf8).write(to: URL(fileURLWithPath: downloaded.zipPath))
        #expect(downloader.cached(newerThan: AppVersion(major: 0, minor: 1, patch: 0)) == nil)
        #expect(!Self.exists(downloaded.directory))
    }

    @Test func cachedIgnoresAReleaseFileFromAnotherTag() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let downloader = UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path)
        let downloaded = try await downloader.download(try Self.release()) { _ in }
        try FileManager.default.moveItem(atPath: downloaded.directory, toPath: temp.path + "/v0.3.0")
        #expect(downloader.cached(newerThan: AppVersion(major: 0, minor: 1, patch: 0)) == nil)
    }

    @Test func cachedWithoutAnUpdatesDirectoryIsNil() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        #expect(UpdateDownloader(http: FakeHTTP(), updatesDirectory: temp.path + "/manca").cached(newerThan: AppVersion(major: 0, minor: 1, patch: 0)) == nil)
    }
}
