import Darwin
import Foundation
import Testing
@testable import CleanerCore

struct UpdateInstallerTests {
    private static func installer(bundle: String, updates: String, launcher: any DetachedLaunching = RecordingLauncher()) -> UpdateInstaller {
        UpdateInstaller(
            context: UpdateContext(currentVersion: AppVersion(major: 0, minor: 1, patch: 0), bundlePath: bundle, processIdentifier: 4242),
            updatesDirectory: updates,
            launcher: launcher)
    }

    private static func update(bundle: String) throws -> VerifiedUpdate {
        let name = AvailableRelease.assetName(for: "v0.2.0")
        let release = AvailableRelease(
            version: AppVersion(major: 0, minor: 2, patch: 0),
            pageURL: try #require(URL(string: "https://github.com/markjackmilian/mjm.cleaner/releases/tag/v0.2.0")),
            assetName: name, assetURL: try #require(URL(string: "https://github.com/x/\(name)")),
            size: 1, sha256: String(repeating: "a", count: 64))
        return VerifiedUpdate(release: release, bundlePath: bundle)
    }

    @Test func writableFolderInstallsInPlace() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let bundle = try temp.directory("Applications/mjm.cleaner.app")
        #expect(Self.installer(bundle: bundle, updates: temp.path + "/updates").mode() == .inPlace)
    }

    @Test func readOnlyFolderNeedsAManualInstall() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let bundle = try temp.directory("Applications/mjm.cleaner.app")
        chmod(temp.path + "/Applications", 0o555)
        guard case .manual = Self.installer(bundle: bundle, updates: temp.path + "/updates").mode() else {
            Issue.record("una cartella in sola lettura non permette l'installazione sul posto")
            return
        }
    }

    @Test func translocatedAppNeedsAManualInstall() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let bundle = try temp.directory("AppTranslocation/ABC/d/mjm.cleaner.app")
        guard case .manual = Self.installer(bundle: bundle, updates: temp.path + "/updates").mode() else {
            Issue.record("un'app in App Translocation non si sostituisce sul posto")
            return
        }
    }

    @Test func executableOutsideABundleNeedsAManualInstall() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let binary = try temp.file("bin/MjmCleaner")
        guard case .manual = Self.installer(bundle: binary, updates: temp.path + "/updates").mode() else {
            Issue.record("senza bundle .app non c'è nulla da sostituire")
            return
        }
    }

    @Test func launchesACopyOfTheBundledScriptWithItsArgumentsOnly() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let bundle = try temp.directory("Applications/mjm.cleaner.app")
        let updates = try temp.directory("updates")
        try temp.file("updates/install-result", contents: "ok v0.1.0")
        let launcher = RecordingLauncher()
        let fresh = updates + "/v0.2.0/expanded/mjm.cleaner.app"
        try Self.installer(bundle: bundle, updates: updates, launcher: launcher).launch(try Self.update(bundle: fresh))

        let (executable, arguments, environment) = try #require(launcher.recorded.first)
        #expect(executable == "/bin/sh")
        #expect(Array(arguments.dropFirst()) == ["4242", bundle, fresh, "v0.2.0", updates, "150"])
        #expect(environment == ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        let script = try #require(arguments.first)
        #expect(script.hasSuffix("/update-install.sh"))
        let bundled = try #require(Bundle.module.url(forResource: "update-install", withExtension: "sh"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: script)) == Data(contentsOf: bundled))
        #expect(!FileManager.default.fileExists(atPath: updates + "/install-result"), "un esito vecchio va cancellato")
    }

    @Test func manualModeNeverLaunchesTheScript() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let bundle = try temp.directory("AppTranslocation/x/mjm.cleaner.app")
        let launcher = RecordingLauncher()
        #expect(throws: UpdateError.self) {
            try Self.installer(bundle: bundle, updates: temp.path, launcher: launcher).launch(try Self.update(bundle: "/x.app"))
        }
        #expect(launcher.recorded.isEmpty)
    }

    @Test(arguments: [
        ("ok v0.2.0\n", InstallOutcome.succeeded(AppVersion(major: 0, minor: 2, patch: 0))),
        ("failed move-new\n", InstallOutcome.failed(step: "move-new")),
    ])
    func readsTheOutcomeOnceAndDeletesIt(text: String, expected: InstallOutcome) throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.file("install-result", contents: text)
        let installer = Self.installer(bundle: "/Applications/mjm.cleaner.app", updates: temp.path)
        #expect(installer.takeOutcome() == expected)
        #expect(installer.takeOutcome() == nil)
    }

    @Test(arguments: ["", "ok", "ok 0.2", "boh v0.2.0", "failed a b"])
    func unreadableOutcomeIsIgnored(text: String) throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.file("install-result", contents: text)
        #expect(Self.installer(bundle: "/Applications/mjm.cleaner.app", updates: temp.path).takeOutcome() == nil)
    }
}
