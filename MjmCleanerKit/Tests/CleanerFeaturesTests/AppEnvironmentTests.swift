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
        let store = FakeSettingsStore(initial)
        let environment = try makeEnvironment(settings: store)

        #expect(environment.expandedProjectRoots() == ["/Users/tester/src", "/Volumes/Dati/progetti"])
        #expect(environment.categories().map(\.id) == [
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads", "large-files",
        ])
        #expect(environment.categories().first { $0.id == "project-build-output" }?.rules.map(\.root)
            == ["/Users/tester/src", "/Volumes/Dati/progetti"])

        // Ogni lettura segue le impostazioni salvate nel frattempo.
        var changed = initial
        changed.projectRoots = ["~/altro"]
        try store.save(changed)

        #expect(environment.expandedProjectRoots() == ["/Users/tester/altro"])
        #expect(environment.categories().first { $0.id == "project-build-output" }?.rules.map(\.root) == ["/Users/tester/altro"])
    }

    // Solo Swift (review del Task 2): la home passata a `live` arriva alla deny-list del `clean` e
    // all'espansore. La home passa da `realpath` perché il test riguarda il passaggio della home,
    // non la sua grafia: dal piano APFS la deny-list riconosce anche una home sotto un collegamento
    // (/var → /private/var), confrontandola nella grafia del disco (spec §12).
    @Test func liveCompositionUsesTheGivenHomeForTheGuardAndTheExpander() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        guard let resolved = realpath(directory.path, nil) else {
            throw UnexpectedTestError(description: "realpath non riuscito")
        }
        defer { free(resolved) }
        let home = String(cString: resolved) + "/home"
        let kept = home + "/Documents/keep.txt"
        let cache = home + "/Library/Caches/app/x.bin"
        for file in [kept, cache] {
            try FileManager.default.createDirectory(atPath: PathText.parent(file) ?? home, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: URL(fileURLWithPath: file))
        }

        let environment = try await AppEnvironment.live(
            paths: AppPaths(supportDirectory: directory.path + "/dati"), home: home, tempDirectory: directory.path + "/tmp")
        var settings = CleanerSettings()
        settings.projectRoots = ["~/src"]
        try environment.settings.save(settings)
        let report = await environment.clean.clean(
            [
                CategorySelection(categoryId: "prova", items: [
                    ScanItem(path: kept, sizeBytes: 1, isDirectory: false, declaredRoot: home + "/Documents"),
                    ScanItem(path: cache, sizeBytes: 1, isDirectory: false, declaredRoot: home + "/Library/Caches"),
                ]),
            ],
            progress: nil,
            journal: nil)

        #expect(environment.expandedProjectRoots() == [home + "/src"])
        #expect(FileManager.default.fileExists(atPath: kept))
        #expect(!FileManager.default.fileExists(atPath: cache))
        #expect(report.itemsDeleted == 1)
    }

    /// Spec `2026-10-20-confirmation-containment-design.md`: in `live` il passo 3 risolve le root con
    /// lo stesso `PathGuard` del motore, quindi un collegamento reale porta dove porta.
    @Test func liveRootsFollowARealLink() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        guard let resolved = realpath(directory.path, nil) else {
            throw UnexpectedTestError(description: "realpath non riuscito")
        }
        defer { free(resolved) }
        let home = String(cString: resolved) + "/home"
        try FileManager.default.createDirectory(atPath: home + "/Dati/cache", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: home + "/.cache", withDestinationPath: home + "/Dati/cache")

        let environment = try await AppEnvironment.live(
            paths: AppPaths(supportDirectory: directory.path + "/dati"), home: home, tempDirectory: directory.path + "/tmp")

        #expect(environment.roots.resolvedRoot(home + "/.cache") == home + "/Dati/cache")
        #expect(environment.roots.resolvedRoot(home + "/Dati") == home + "/Dati")
    }

    @Test func defaultPathsIsolatesDebugDataFromRelease() {
        let debug = AppEnvironment.defaultPaths(bundleIdentifier: "com.mjm.cleaner.debug")
        let release = AppEnvironment.defaultPaths(bundleIdentifier: "com.mjm.cleaner")

        #expect(debug.supportDirectory.hasSuffix("/com.mjm.cleaner.debug"))
        #expect(debug.databaseFile == PathText.join(debug.supportDirectory, "history.db"))
        #expect(debug.settingsFile == PathText.join(debug.supportDirectory, "settings.json"))
        #expect(debug.logsDirectory == PathText.join(debug.supportDirectory, "logs"))
        #expect(debug.supportDirectory != release.supportDirectory)
        #expect(release.supportDirectory.hasSuffix("/com.mjm.cleaner"))
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
