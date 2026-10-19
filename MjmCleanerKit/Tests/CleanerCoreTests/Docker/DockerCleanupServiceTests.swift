import Testing
@testable import CleanerCore

struct DockerCleanupServiceTests {
    private static let rawPath = "/Users/tester/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
    private static let contextCommand = "context inspect --format {{json .}}"
    private static let desktopEngine = DockerEngine(serverVersion: "29.8.0", operatingSystem: "Docker Desktop", id: "5f0d6c1e-desktop")
    private static let orbStackEngine = DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack", id: "b2756783-orbstack")

    private struct NoProcess: ProcessRunning {
        let calls = Recorder<[String]>()

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            calls.append([executable] + arguments)
            return ProcessResult(exitCode: 0, standardOutput: "16\t" + DockerCleanupServiceTests.rawPath, standardError: "", timedOut: false)
        }
    }

    /// Un servizio su `cli`, il motore del contesto attivo `desktop-linux`.
    private func service(
        _ fs: InMemoryFileSystem,
        _ cli: FakeDockerCli,
        du: NoProcess = NoProcess(),
        diskFiles: (any FileSystem)? = nil
    ) -> DockerCleanupService {
        service(fs, docker: FakeDockerContexts(active: "desktop-linux", [(FakeDockerContexts.desktopLinux, cli)]), du: du, diskFiles: diskFiles)
    }

    private func service(
        _ fs: InMemoryFileSystem,
        docker: any DockerCommandRunning,
        du: NoProcess = NoProcess(),
        diskFiles: (any FileSystem)? = nil
    ) -> DockerCleanupService {
        DockerCleanupService(
            collector: DockerInventoryCollector(cli: docker, fileSystem: fs),
            scanner: ProjectReferenceScanner(fileSystem: fs),
            disk: DiskUsageProbe(runner: du, fileSystem: diskFiles ?? fs, diskImagePath: Self.rawPath),
            executor: DockerCleanExecutor(cli: docker, clock: SystemWallClock()),
            contexts: DockerContextReader(cli: docker, homeDirectory: "/Users/tester"))
    }

    /// Docker Desktop (`desktop-linux`, attivo) con il caso reale delle fixture e OrbStack
    /// (`orbstack`) con lo stesso caso: un comando arrivato al motore sbagliato troverebbe risposta.
    private func twoEngines() throws -> (docker: FakeDockerContexts, desktop: FakeDockerCli, orbStack: FakeDockerCli) {
        let desktop = try FakeDockerCli.withRealCase()
            .on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.0", id: Self.desktopEngine.id))
        let orbStack = try FakeDockerCli.withRealCase()
            .on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.2", "OrbStack", id: Self.orbStackEngine.id))
        let docker = FakeDockerContexts(active: "desktop-linux", [
            (FakeDockerContexts.desktopLinux, desktop),
            (FakeDockerContexts.orbstack, orbStack),
        ])
        return (docker, desktop, orbStack)
    }

    @Test func analysisClassifiesWithTheReferencesFoundInTheProjects() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("/Users/tester/projects/orbit/Orbit.AppHost/Program.cs", text: """
            var builder = DistributedApplication.CreateBuilder(args);
            builder.AddKeycloak("keycloak").WithImageTag("26.6");
            """)

        let analysis = try await service(fs, FakeDockerCli.withRealCase()).analyze(["/Users/tester/projects"])

        let keycloak = try #require(analysis.candidates.first { $0.displayName == "quay.io/keycloak/keycloak:26.6" })
        #expect(keycloak.verdict == .keep)
        #expect(keycloak.reason.contains("Program.cs:2"))
    }

    @Test func analysisMeasuresTheDiskImage() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 100)

        let analysis = try await service(fs, FakeDockerCli.withRealCase()).analyze([])

        #expect(analysis.engine == DockerEngine(serverVersion: "29.8.0", operatingSystem: "Docker Desktop"))
        #expect(analysis.disk?.allocatedBytes == Int64(16 * 1024))
        #expect(analysis.disk?.apparentBytes == 100)
        #expect(analysis.snapshot.df.images == 5_840_000_000)
    }

    /// Sul Mac dell'utente Docker Desktop ha lasciato un Docker.raw: con OrbStack non si misura, e
    /// il disco non viene nemmeno guardato (né `fileExists`/`itemInfo`, né `du`).
    @Test func orbStackHasNoDiskToMeasureEvenWithADockerRawLeftBehind() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 100)
        let diskFiles = AccessLogFileSystem(fs)
        let du = NoProcess()
        let cli = try FakeDockerCli.withRealCase().on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.2", "OrbStack"))
        let docker = service(fs, cli, du: du, diskFiles: diskFiles)

        let analysis = try await docker.analyze([])
        let after = try await docker.measureDisk(for: analysis.engine)

        #expect(analysis.engine.kind == .orbStack)
        #expect(analysis.disk == nil)
        #expect(after == nil)
        #expect(diskFiles.paths.values.isEmpty)
        #expect(du.calls.values.isEmpty)
    }

    @Test func aDaemonThatDoesNotAnswerNamesTheEngineOfTheActiveContext() async {
        let cli = FakeDockerCli()
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notRunning) }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), cli).analyze([])
        }

        #expect(error == DockerUnavailableError("Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."))
    }

    /// Senza un contesto non si può fissare l'analisi: si ferma prima di parlare con un daemon.
    @Test func anUnreadableContextStopsTheAnalysis() async {
        let cli = FakeDockerCli()
            .on(Self.contextCommand) { FakeDockerCli.fail(#"context "gone": context not found"#) }

        let error = await #expect(throws: DockerCommandError.self) {
            try await service(InMemoryFileSystem(), docker: cli).analyze([])
        }

        #expect(error == DockerCommandError(#"docker context inspect: context "gone": context not found"#))
        #expect(cli.commandLines == [Self.contextCommand])
    }

    @Test func aContextWithoutAValidNameStopsTheAnalysis() async {
        let cli = FakeDockerCli()
            .on(Self.contextCommand, #"{"Name":"","Metadata":{},"Endpoints":{"docker":{"Host":"unix:///var/run/docker.sock"}}}"#)

        let error = await #expect(throws: DockerOutputError.self) {
            try await service(InMemoryFileSystem(), docker: cli).analyze([])
        }

        #expect(error == DockerOutputError("Nome del contesto Docker non valido: «»."))
        #expect(cli.commandLines == [Self.contextCommand])
    }

    @Test func aMissingDockerStopsAtTheContextRead() async {
        let cli = FakeDockerCli()
            .on(Self.contextCommand) { throw DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled) }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), docker: cli).analyze([])
        }

        #expect(error == DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled))
        #expect(cli.commandLines == [Self.contextCommand])
    }

    @Test func aMissingDockerIsNeverRewritten() async {
        let cli = FakeDockerCli()
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled) }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), cli).analyze([])
        }

        #expect(error == DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled))
    }

    /// OrbStack, avviandosi, cambia il contesto attivo subito dopo che l'analisi lo ha letto: ogni
    /// comando successivo resta su `desktop-linux`, e il bersaglio è Docker Desktop.
    @Test func everyAnalysisCommandStaysOnTheContextReadAtTheStart() async throws {
        let (docker, desktop, orbStack) = try twoEngines()
        desktop.on(FakeDockerCli.infoCommand) {
            docker.activate("orbstack")
            return FakeDockerCli.ok(FakeDockerCli.info("29.8.0", id: Self.desktopEngine.id))
        }

        let analysis = try await service(InMemoryFileSystem(), docker: docker).analyze([])

        #expect(analysis.target == DockerTarget(context: FakeDockerContexts.desktopLinux, engine: Self.desktopEngine))
        #expect(!analysis.candidates.isEmpty)
        #expect(docker.calls.first == ["context", "inspect", "--format", "{{json .}}"])
        #expect(docker.calls.dropFirst().allSatisfy { $0.starts(with: ["--context", "desktop-linux"]) })
        #expect(docker.calls.count > 2)
        #expect(orbStack.calls.isEmpty)
    }

    /// Docker Desktop si ferma e OrbStack prende il contesto attivo: l'errore nomina il motore
    /// analizzato, non quello che risponde ora.
    @Test func aStoppedEngineIsNamedFromTheContextReadAtTheStart() async throws {
        let (docker, desktop, orbStack) = try twoEngines()
        desktop.on(FakeDockerCli.infoCommand) {
            docker.activate("orbstack")
            throw DockerUnavailableError(DockerUnavailableError.notRunning)
        }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), docker: docker).analyze([])
        }

        #expect(error == DockerUnavailableError("Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."))
        #expect(orbStack.calls.isEmpty)
    }

    /// Un'immagine, un volume e la cache di build dell'analisi, da cancellare.
    private func deletable(_ analysis: DockerAnalysis) throws -> (image: DockerCandidate, volume: DockerCandidate, buildCache: DockerCandidate) {
        (
            try #require(analysis.candidates.first { $0.kind == .image && $0.verdict != .keep }),
            try #require(analysis.candidates.first { $0.kind == .volume && $0.verdict != .keep }),
            try #require(analysis.candidates.first { $0.kind == .buildCache }))
    }

    /// I comandi che cancellano, fra quelli arrivati a `cli`.
    private func deletions(_ cli: FakeDockerCli) -> [String] {
        cli.commandLines.filter { $0.hasPrefix("rmi ") || $0.hasPrefix("volume rm ") || $0.hasPrefix("builder prune") }
    }

    /// Il caso del 2026-10-19: dopo l'analisi di Docker Desktop, OrbStack si avvia e prende il
    /// contesto attivo. «Elimina» cancella su Docker Desktop, ciò che l'utente ha confermato, e
    /// OrbStack non riceve nemmeno un comando, anche se accetterebbe ogni cancellazione.
    @Test func aContextSwitchBetweenAnalysisAndDeletionLeavesTheOtherEngineAlone() async throws {
        let (docker, desktop, orbStack) = try twoEngines()
        for cli in [desktop, orbStack] {
            cli.onPrefix("rmi ") { _ in FakeDockerCli.ok("Deleted") }
                .onPrefix("volume rm ") { arguments in FakeDockerCli.ok(arguments.last ?? "") }
                .on("builder prune -f", "Total reclaimed space: 106.9MB")
        }
        let cleanup = service(InMemoryFileSystem(), docker: docker)
        let analysis = try await cleanup.analyze([])
        let (image, volume, buildCache) = try deletable(analysis)

        docker.activate("orbstack")
        let result = try await cleanup.execute([image, volume, buildCache], on: analysis.target, progress: nil)

        #expect(result.report.itemsDeleted == 3)
        #expect(deletions(desktop) == ["rmi \(image.id)", "volume rm \(volume.id)", "builder prune -f"])
        #expect(orbStack.calls.isEmpty)
    }

    /// Dopo il cambio Docker Desktop è anche spento: non si cancella nulla, né lì né su OrbStack, e
    /// l'errore nomina Docker Desktop.
    @Test func aStoppedEngineAfterTheSwitchDeletesNothingAnywhere() async throws {
        let (docker, desktop, orbStack) = try twoEngines()
        let cleanup = service(InMemoryFileSystem(), docker: docker)
        let analysis = try await cleanup.analyze([])
        let (image, volume, buildCache) = try deletable(analysis)

        docker.activate("orbstack")
        desktop.on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notRunning) }
        let error = await #expect(throws: DockerUnavailableError.self) {
            try await cleanup.execute([image, volume, buildCache], on: analysis.target, progress: nil)
        }

        #expect(error == DockerUnavailableError("Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."))
        #expect(deletions(desktop).isEmpty)
        #expect(orbStack.calls.isEmpty)
    }
}
