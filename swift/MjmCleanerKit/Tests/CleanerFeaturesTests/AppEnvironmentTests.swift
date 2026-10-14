import CleanerCore
import Darwin
import Foundation
import Testing
@testable import CleanerFeatures

/// La composizione (`AppServices.CreateAsync`) e la vista d'errore dell'avvio (`FatalErrorWindow`).
struct AppEnvironmentTests {
    @Test func liveCompositionKeepsEveryFileUnderTheGivenDataFolder() async throws {
        let home = try await TestHome.create()
        defer { home.remove() }
        let paths = home.environment.paths

        #expect(FileManager.default.fileExists(atPath: paths.databaseFile))
        #expect(try await home.environment.history.totalBytesFreed() == 0)

        var settings = CleanerSettings()
        settings.projectRoots = ["~/src"]
        try home.environment.settings.save(settings)

        #expect(FileManager.default.fileExists(atPath: paths.settingsFile))
        #expect(home.environment.settings.load().projectRoots == ["~/src"])
    }

    @Test func categoriesAndProjectRootsFollowTheCurrentSettings() throws {
        var initial = CleanerSettings()
        initial.projectRoots = ["~/src", "/Volumes/Dati/progetti"]
        let environment = try makeEnvironment(settings: FakeSettingsStore(initial))

        #expect(environment.expandedProjectRoots() == ["/Users/tester/src", "/Volumes/Dati/progetti"])
        #expect(environment.categories().map(\.id) == [
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads-large",
        ])
    }

    @Test func defaultPathsUseTheBundleIdentifierOrTheProvisionalOne() {
        #expect(AppEnvironment.defaultPaths(bundleIdentifier: "com.esempio.app") == AppPaths.forBundleIdentifier("com.esempio.app"))
        #expect(AppEnvironment.defaultPaths(bundleIdentifier: nil) == AppPaths.forBundleIdentifier("com.mjm.cleaner"))
    }

    @Test func liveCompositionFailsWhenTheDataFolderIsUnusable() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let blocker = PathText.join(directory.path, "file")
        try Data().write(to: URL(fileURLWithPath: blocker))
        let paths = AppPaths(supportDirectory: PathText.join(blocker, "dati"))

        await #expect(throws: (any Error).self) {
            _ = try await AppEnvironment.live(paths: paths)
        }
    }

    @Test func startupFailureNamesThePathAndTheReason() {
        let paths = AppPaths(supportDirectory: "/Users/tester/Library/Application Support/com.mjm.cleaner")

        let message = StartupFailure.message(paths: paths, error: FileSystemError(code: EACCES, path: paths.databaseFile))

        #expect(StartupFailure.title == "Impossibile accedere ai dati dell'applicazione")
        #expect(message == "Percorso: /Users/tester/Library/Application Support/com.mjm.cleaner\n\nMotivo: \(String(cString: strerror(EACCES)))")
    }
}
