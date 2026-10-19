import Foundation
import Testing
@testable import CleanerCore

struct SettingsStoreTests {
    private static let paths = AppPaths(supportDirectory: "/Users/tester/Library/Application Support/com.mjm.cleaner")

    /// Legge il JSON salvato come dizionario: verifica il formato senza dipendere da spaziature
    /// (JSONEncoder scrive `"Chiave" : valore`, System.Text.Json scriveva `"Chiave": valore`).
    private func savedJSON(_ fs: InMemoryFileSystem) throws -> [String: Any] {
        let data = try fs.readData(Self.paths.settingsFile)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func loadReturnsDefaultsWhenFileMissing() {
        let settings = SettingsStore(fileSystem: InMemoryFileSystem(), paths: Self.paths).load()
        #expect(settings.projectRoots.isEmpty)
        #expect(settings.downloadsMinAgeDays == 90)
        #expect(settings.logsMinAgeDays == 30)
        #expect(settings.nuGetMinAgeDays == 180)
        #expect(settings.largeFileThresholdBytes == 500 * 1024 * 1024)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = SettingsStore(fileSystem: InMemoryFileSystem(), paths: Self.paths)
        var original = CleanerSettings()
        original.projectRoots = ["/Users/tester/projects"]
        original.downloadsMinAgeDays = 30
        original.selectedCategoryIds = ["system-caches", "dev-caches"]

        try store.save(original)
        let loaded = store.load()

        #expect(loaded.projectRoots == ["/Users/tester/projects"])
        #expect(loaded.downloadsMinAgeDays == 30)
        #expect(loaded.selectedCategoryIds == ["system-caches", "dev-caches"])
    }

    @Test func loadReturnsDefaultsWhenFileIsCorrupt() {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: "{ questo non è json")
        #expect(SettingsStore(fileSystem: fs, paths: Self.paths).load().downloadsMinAgeDays == 90)
    }

    @Test func appearanceDefaultsToAuto() {
        #expect(CleanerSettings().appearance == .auto)
    }

    @Test func legacyFileWithoutAppearanceLoadsAsAuto() {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: #"{ "DownloadsMinAgeDays": 12 }"#)
        let settings = SettingsStore(fileSystem: fs, paths: Self.paths).load()
        #expect(settings.downloadsMinAgeDays == 12)
        #expect(settings.appearance == .auto)
    }

    @Test func appearanceRoundTripsAsReadableString() throws {
        let fs = InMemoryFileSystem()
        let store = SettingsStore(fileSystem: fs, paths: Self.paths)
        var settings = CleanerSettings()
        settings.appearance = .dark

        try store.save(settings)

        #expect(try savedJSON(fs)["Appearance"] as? String == "Dark")
        #expect(store.load().appearance == .dark)
    }

    @Test(arguments: [#""Darkk""#, "7", "-1", "null", "true", #""""#, #""1""#, #"{ "x": 1 }"#, #"[ "Dark" ]"#])
    func unknownAppearanceValueFallsBackToAutoAndKeepsTheOtherSettings(appearanceJSON: String) {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: #"{ "DownloadsMinAgeDays": 12, "Appearance": "# + appearanceJSON + #", "LogsMinAgeDays": 5 }"#)

        let settings = SettingsStore(fileSystem: fs, paths: Self.paths).load()

        #expect(settings.appearance == .auto)
        #expect(settings.downloadsMinAgeDays == 12)
        #expect(settings.logsMinAgeDays == 5)
    }

    @Test(arguments: [
        ("dark", AppearancePreference.dark),
        ("DARK", .dark),
        ("Light", .light),
        ("auto", .auto),
    ])
    func appearanceIsReadCaseInsensitively(text: String, expected: AppearancePreference) {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: #"{ "Appearance": ""# + text + #"" }"#)
        #expect(SettingsStore(fileSystem: fs, paths: Self.paths).load().appearance == expected)
    }

    @Test(arguments: AppearancePreference.allCases)
    func appearanceRoundTripsForEveryValue(preference: AppearancePreference) throws {
        let fs = InMemoryFileSystem()
        let store = SettingsStore(fileSystem: fs, paths: Self.paths)
        var settings = CleanerSettings()
        settings.appearance = preference
        settings.downloadsMinAgeDays = 7

        try store.save(settings)

        #expect(try savedJSON(fs)["Appearance"] as? String == preference.rawValue)
        let loaded = store.load()
        #expect(loaded.appearance == preference)
        #expect(loaded.downloadsMinAgeDays == 7)
    }

    @Test func appPathsLiveUnderApplicationSupport() {
        let paths = AppPaths.forBundleIdentifier("com.mjm.cleaner")
        #expect(paths.supportDirectory.hasSuffix("/Library/Application Support/com.mjm.cleaner"))
        #expect(paths.databaseFile.hasSuffix("history.db"))
        #expect(paths.settingsFile.hasSuffix("settings.json"))
        #expect(paths.logsDirectory.hasSuffix("logs"))
    }

    @Test func updateChecksAreOnByDefaultWithNoPreviousCheck() {
        let settings = CleanerSettings()
        #expect(settings.automaticUpdateChecks)
        #expect(settings.lastUpdateCheck == nil)
    }

    @Test func legacyFileWithoutUpdateFieldsKeepsItsValuesAndChecksUpdates() {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: #"{ "LogsMinAgeDays": 7 }"#)
        let settings = SettingsStore(fileSystem: fs, paths: Self.paths).load()
        #expect(settings.logsMinAgeDays == 7)
        #expect(settings.automaticUpdateChecks)
        #expect(settings.lastUpdateCheck == nil)
    }

    @Test func updateFieldsRoundTripUnderTheirKeys() throws {
        let fs = InMemoryFileSystem()
        let store = SettingsStore(fileSystem: fs, paths: Self.paths)
        var settings = CleanerSettings()
        settings.automaticUpdateChecks = false
        settings.lastUpdateCheck = Date(timeIntervalSince1970: 1_790_000_000)
        try store.save(settings)

        let json = try savedJSON(fs)
        #expect(json["AutomaticUpdateChecks"] as? Bool == false)
        #expect(json["LastUpdateCheck"] != nil)
        let loaded = store.load()
        #expect(loaded.automaticUpdateChecks == false)
        #expect(loaded.lastUpdateCheck == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func neverCheckedLeavesNoLastCheckKey() throws {
        let fs = InMemoryFileSystem()
        try SettingsStore(fileSystem: fs, paths: Self.paths).save(CleanerSettings())
        #expect(try savedJSON(fs)["LastUpdateCheck"] == nil)
    }
}
