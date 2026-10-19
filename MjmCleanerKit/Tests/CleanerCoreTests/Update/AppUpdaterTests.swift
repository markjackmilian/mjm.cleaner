import CryptoKit
import Foundation
import Testing
@testable import CleanerCore

/// La composizione: le parti sono verificate nei propri test, qui si controlla che siano collegate.
struct AppUpdaterTests {
    private static let payload = Data("zip della v0.2.0".utf8)

    private static func feedBody() -> Data {
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return releaseJSON(tag: "v0.2.0", assets: [asset("mjm.cleaner-v0.2.0-macos-universal.zip", size: Int64(payload.count), digest: "sha256:" + digest)])
    }

    private static func updater(in temp: TemporaryDirectory, current: AppVersion = AppVersion(major: 0, minor: 1, patch: 0), launcher: RecordingLauncher = RecordingLauncher()) throws -> AppUpdater {
        let bundle = try temp.directory("Applications/mjm.cleaner.app")
        return AppUpdater(
            context: UpdateContext(currentVersion: current, bundlePath: bundle, processIdentifier: 7),
            paths: AppPaths(supportDirectory: temp.path + "/support"),
            http: FakeHTTP(body: feedBody(), payload: payload),
            runner: FakeUpdateTools(bundle: makeFakeBundle()),
            launcher: launcher)
    }

    @Test func checkDownloadVerifyAndInstallTheNewerRelease() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let launcher = RecordingLauncher()
        let updater = try Self.updater(in: temp, launcher: launcher)

        let release = try #require(try await updater.check())
        #expect(release.tag == "v0.2.0")
        let verified = try await updater.prepare(release) { _ in }
        #expect(verified.bundlePath == temp.path + "/support/updates/v0.2.0/expanded/mjm.cleaner.app")
        #expect(updater.installMode() == .inPlace)
        try updater.install(verified)
        #expect(launcher.recorded.count == 1)
    }

    @Test func cachedUpdateSurvivesARestart() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let first = try Self.updater(in: temp)
        let release = try #require(try await first.check())
        let verified = try await first.prepare(release) { _ in }

        #expect(await (try Self.updater(in: temp)).cachedUpdate() == verified)
    }

    @Test func upToDateCheckClearsLeftoverDownloads() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let old = try Self.updater(in: temp)
        _ = try await old.prepare(try #require(try await old.check())) { _ in }

        let current = try Self.updater(in: temp, current: AppVersion(major: 0, minor: 2, patch: 0))
        #expect(try await current.check() == nil)
        #expect(!FileManager.default.fileExists(atPath: temp.path + "/support/updates/v0.2.0"))
    }

    @Test func installOutcomeIsReadFromTheUpdatesDirectory() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.file("support/updates/install-result", contents: "failed copy\n")
        #expect(try Self.updater(in: temp).takeInstallOutcome() == .failed(step: "copy"))
    }
}
