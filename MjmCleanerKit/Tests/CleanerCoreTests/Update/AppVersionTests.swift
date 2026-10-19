import Testing
@testable import CleanerCore

struct AppVersionTests {
    @Test(arguments: ["1.2.3", "v1.2.3"])
    func parsesWithAndWithoutTheTagPrefix(text: String) throws {
        let version = try #require(AppVersion(text))
        #expect(version == AppVersion(major: 1, minor: 2, patch: 3))
        #expect(version.description == "1.2.3")
        #expect(version.tag == "v1.2.3")
    }

    @Test(arguments: [
        "", "v", "1.2", "1.2.3.4", "1..3", "v1.2.3-rc1", "1.2.3+5", " 1.2.3", "1.2.3 ", "V1.2.3",
        "vv1.2.3", "1.-2.3", "1.+2.3", "1.2.x", "1234567890.0.0", "١.2.3",
    ])
    func rejectsEverythingElse(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func comparesFieldsAsNumbers() throws {
        let older = try #require(AppVersion("0.9.0"))
        let newer = try #require(AppVersion("0.10.0"))
        #expect(older < newer)
        #expect(try #require(AppVersion("1.0.0")) > newer)
        #expect(try #require(AppVersion("0.10.1")) > newer)
        #expect(!(newer < newer))
    }
}

struct UpdateContextTests {
    @Test func existsOnlyForTheReleaseBundle() throws {
        let context = try #require(UpdateContext.make(
            bundleIdentifier: "com.mjm.cleaner", shortVersion: "0.1.0",
            bundlePath: "/Applications/mjm.cleaner.app", processIdentifier: 42))
        #expect(context.currentVersion == AppVersion(major: 0, minor: 1, patch: 0))
        #expect(context.bundlePath == "/Applications/mjm.cleaner.app")
        #expect(context.processIdentifier == 42)
    }

    @Test(arguments: [("com.mjm.cleaner.debug", "0.1.0"), ("com.mjm.cleaner", "1.0"), ("com.mjm.cleaner", nil)] as [(String?, String?)])
    func debugBuildsAndUnreadableVersionsNeverUpdate(identifier: String?, version: String?) {
        #expect(UpdateContext.make(bundleIdentifier: identifier, shortVersion: version, bundlePath: "/x.app", processIdentifier: 1) == nil)
    }

    @Test func bundlePathLosesTheTrailingSlashOfDirectoryURLs() {
        let context = UpdateContext.make(
            bundleIdentifier: "com.mjm.cleaner", shortVersion: "0.1.0", bundlePath: "/Applications/mjm.cleaner.app/", processIdentifier: 1)
        #expect(context?.bundlePath == "/Applications/mjm.cleaner.app")
    }

    @Test func missingBundleIdentifierNeverUpdates() {
        #expect(UpdateContext.make(bundleIdentifier: nil, shortVersion: "0.1.0", bundlePath: "/x.app", processIdentifier: 1) == nil)
    }

    @Test func updatesLiveUnderApplicationSupportNotCaches() {
        let paths = AppPaths(supportDirectory: "/Users/tester/Library/Application Support/com.mjm.cleaner")
        #expect(paths.updatesDirectory == "/Users/tester/Library/Application Support/com.mjm.cleaner/updates")
    }
}
