import CleanerCore
import Foundation

/// Porting di `AppServices`: la composizione manuale delle dipendenze. Per un'applicazione con un
/// solo grafo di oggetti un contenitore di inversione del controllo aggiungerebbe solo
/// indirezione. I servizi sono protocolli del Core, così i test dei modelli usano doppi.
public struct AppEnvironment: Sendable {
    public let scan: any ScanPerforming
    public let clean: any CleanPerforming
    public let history: any HistoryStoring
    public let sessionLog: any SessionLogWriting
    public let settings: any SettingsStoring
    public let runningApps: any RunningAppsProbing
    public let docker: any DockerCleanupServing
    public let xcode: any XcodeCleanupServing
    public let paths: AppPaths
    public let clock: any WallClock
    private let expander: PathExpander

    public init(
        scan: any ScanPerforming,
        clean: any CleanPerforming,
        history: any HistoryStoring,
        sessionLog: any SessionLogWriting,
        settings: any SettingsStoring,
        runningApps: any RunningAppsProbing,
        docker: any DockerCleanupServing,
        xcode: any XcodeCleanupServing,
        paths: AppPaths,
        clock: any WallClock,
        expander: PathExpander
    ) {
        self.scan = scan
        self.clean = clean
        self.history = history
        self.sessionLog = sessionLog
        self.settings = settings
        self.runningApps = runningApps
        self.docker = docker
        self.xcode = xcode
        self.paths = paths
        self.clock = clock
        self.expander = expander
    }

    /// `BuildCategories()`: il catalogo con le impostazioni correnti.
    public func categories() -> [CleanupCategory] {
        CategoryCatalog.build(settings.load(), expander)
    }

    /// Le stesse cartelle progetto di bin/obj, espanse: dove cercare le immagini Docker citate.
    public func expandedProjectRoots() -> [String] {
        settings.load().projectRoots.map(expander.expand)
    }

    /// `~/Library/Application Support/<bundle id>/` (spec §4.4). Senza bundle id, per esempio
    /// sotto `swift test`, vale quello provvisorio dell'app.
    public static func defaultPaths(bundleIdentifier: String?) -> AppPaths {
        AppPaths.forBundleIdentifier(bundleIdentifier ?? "com.mjm.cleaner")
    }

    /// `AppServices.CreateAsync`: lo stesso grafo, con un'unica fonte per la home (home e cartella
    /// temporanea si sostituiscono solo nei test). Lancia se la cartella dati o lo storico non si
    /// aprono: l'app mostra allora la vista d'errore (`StartupFailure`).
    public static func live(
        paths: AppPaths,
        home: String = NSHomeDirectory(),
        tempDirectory: String = NSTemporaryDirectory()
    ) async throws -> AppEnvironment {
        let fileSystem = LocalFileSystem()
        let clock = SystemWallClock()
        let links = FileSystemLinkInspector()
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
        let scanner = RuleScanner(fileSystem: fileSystem, pathGuard: pathGuard, links: links, clock: clock)

        // Docker passa solo dalla CLI: nessun file sotto la cartella di Docker Desktop viene mai
        // cancellato (la deny-list resta invariata); di Docker.raw si legge soltanto la dimensione.
        let processes = ProcessRunner()
        let dockerCli = DockerCli(runner: processes, binaryPath: DockerBinaryLocator.find(fileSystem, homeDirectory: home))
        let docker = DockerCleanupService(
            collector: DockerInventoryCollector(cli: dockerCli, fileSystem: fileSystem),
            scanner: ProjectReferenceScanner(fileSystem: fileSystem),
            disk: DiskUsageProbe(runner: processes, fileSystem: fileSystem, diskImagePath: DiskUsageProbe.defaultPath(home)),
            executor: DockerCleanExecutor(cli: dockerCli, clock: clock))

        // L'esecutore Xcode usa lo stesso collettore e lo stesso PathGuard della scansione
        // (AppServices.cs): ciò che rivalida prima di eliminare è ciò che l'analisi ha mostrato.
        let xcodeCli = XcodeCli(runner: processes, binaryPath: XcodeCli.locateBinary(fileSystem))
        let xcodeMeasures = XcodeSizeProbe(fileSystem: fileSystem, runner: processes, links: links, homeDirectory: home)
        let xcodeFiles = XcodeFileScanner(
            fileSystem: fileSystem, ruleScanner: scanner, pathGuard: pathGuard, links: links,
            sizeProbe: xcodeMeasures, homeDirectory: home)
        let xcodeInventory = XcodeInventoryCollector(cli: xcodeCli, fileScanner: xcodeFiles)
        let xcodeRunning = XcodeRunningProbe(runner: processes)
        let xcode = XcodeCleanupService(
            collector: xcodeInventory,
            runningProbe: xcodeRunning,
            executor: XcodeCleanExecutor(
                cli: xcodeCli,
                collector: xcodeInventory,
                cleanEngine: CleanEngine(fileSystem: fileSystem, pathGuard: pathGuard, clock: clock),
                measures: xcodeMeasures,
                runningProbe: xcodeRunning,
                clock: clock))

        let history = HistoryStore(databaseFile: paths.databaseFile)
        try await history.initialize()

        return AppEnvironment(
            scan: ScanEngine(scanner: scanner),
            clean: CleanEngine(fileSystem: fileSystem, pathGuard: pathGuard, clock: clock),
            history: history,
            sessionLog: SessionLogWriter(fileSystem: fileSystem, paths: paths),
            settings: SettingsStore(fileSystem: fileSystem, paths: paths),
            runningApps: RunningAppsProbe.forCurrentMachine(runner: processes, home: home),
            docker: docker,
            xcode: xcode,
            paths: paths,
            clock: clock,
            expander: try PathExpander(homeDirectory: home, tempDirectory: tempDirectory))
    }
}
