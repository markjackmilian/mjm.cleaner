import Foundation
import Testing
@testable import CleanerCore

struct DockerCleanExecutorTests {
    private static let dfBefore = """
        {"Type":"Images","Size":"5.84GB","Reclaimable":"1GB"}
        {"Type":"Local Volumes","Size":"558.5MB","Reclaimable":"159MB"}
        {"Type":"Build Cache","Size":"106.9MB","Reclaimable":"106.9MB"}
        """

    private static let dfAfter = """
        {"Type":"Images","Size":"5.5GB","Reclaimable":"0B"}
        {"Type":"Local Volumes","Size":"470MB","Reclaimable":"0B"}
        {"Type":"Build Cache","Size":"0B","Reclaimable":"0B"}
        """

    private static let ryukId = DockerFixtures.ryukId

    /// Il bersaglio dell'analisi: Docker Desktop su `desktop-linux`.
    private static let target = DockerTarget(
        context: FakeDockerContexts.desktopLinux,
        engine: DockerEngine(serverVersion: "29.8.0", operatingSystem: "Docker Desktop", id: "5f0d6c1e-desktop"))

    private static let buildCache = DockerCandidate(
        kind: .buildCache, id: DockerClassifier.buildCacheId, displayName: "Cache di build", sizeBytes: 1_000,
        verdict: .delete, ruleId: "build-cache", reason: "m", cost: "c")

    private func image(_ id: String, _ name: String, _ verdict: DockerVerdict = .delete) -> DockerCandidate {
        DockerCandidate(kind: .image, id: id, displayName: name, sizeBytes: 1_000, verdict: verdict, ruleId: "rule", reason: "motivo", cost: "costo")
    }

    private func volume(_ name: String, _ verdict: DockerVerdict = .propose) -> DockerCandidate {
        DockerCandidate(kind: .volume, id: name, displayName: name, sizeBytes: 1_000, verdict: verdict, ruleId: "rule", reason: "motivo", cost: "costo")
    }

    /// CLI del motore analizzato: accetta ogni cancellazione e restituisce il df prima e dopo.
    private func succeedingCli() -> FakeDockerCli {
        let dfCalls = Shared(0)
        return FakeDockerCli()
            .on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.0", id: Self.target.engine.id))
            .on("system df --format {{json .}}") { FakeDockerCli.ok(dfCalls.increment() == 1 ? Self.dfBefore : Self.dfAfter) }
            .onPrefix("rmi ") { _ in FakeDockerCli.ok("Deleted") }
            .onPrefix("volume rm ") { arguments in FakeDockerCli.ok(arguments.last ?? "") }
            .on("builder prune -f", "Total reclaimed space: 106.9MB")
    }

    /// `cli` è il motore di `desktop-linux`; il contesto attivo è `orbstack`, un motore che non
    /// risponde a nulla: un comando senza `--context desktop-linux` non arriva mai a `cli`.
    private static func contexts(_ cli: FakeDockerCli, orbStack: FakeDockerCli = FakeDockerCli()) -> FakeDockerContexts {
        FakeDockerContexts(active: "orbstack", [(FakeDockerContexts.desktopLinux, cli), (FakeDockerContexts.orbstack, orbStack)])
    }

    private func executor(_ cli: FakeDockerCli) -> DockerCleanExecutor {
        DockerCleanExecutor(cli: Self.contexts(cli), clock: FixedWallClock(now: Date(timeIntervalSince1970: 0)))
    }

    private func execute(_ cli: FakeDockerCli, _ selected: DockerCandidate...) async throws -> DockerCleanResult {
        try await executor(cli).execute(selected, on: Self.target, progress: nil)
    }

    @Test func imagesAreRemovedByIdNeverByTag() async throws {
        let cli = succeedingCli()

        _ = try await execute(cli, image(Self.ryukId, "testcontainers/ryuk:0.14.0"))

        #expect(cli.commandLines.contains("rmi \(Self.ryukId)"))
        #expect(!cli.commandLines.contains { $0.contains("ryuk:0.14.0") })
    }

    @Test func noCommandIsEverForcedOrAGlobalPrune() async throws {
        let cli = succeedingCli()

        _ = try await execute(cli, image(Self.ryukId, "ryuk"), volume("old-data"), Self.buildCache)

        for call in cli.calls where call.first == "rmi" || call.first == "volume" {
            #expect(!call.contains("-f"))
            #expect(!call.contains("--force"))
        }
        #expect(!cli.commandLines.contains { $0.hasPrefix("system prune") })
        #expect(!cli.commandLines.contains { $0.contains("--volumes") })
        #expect(!cli.commandLines.contains { $0.contains("-a") && $0.contains("prune") })
    }

    @Test func volumesAndBuildCacheUseTheirOwnCommands() async throws {
        let cli = succeedingCli()

        let result = try await execute(cli, volume("orbit.apphost-751ef8e8e6-storage-data"), Self.buildCache)

        #expect(cli.commandLines.contains("volume rm orbit.apphost-751ef8e8e6-storage-data"))
        #expect(cli.commandLines.contains("builder prune -f"))
        #expect(result.report.itemsDeleted == 2)
    }

    @Test func keepVerdictsAreRefusedWithoutRunningAnything() async throws {
        let cli = succeedingCli()

        let result = try await execute(cli,
            image(DockerFixtures.mssql2025Id, "mssql 2025", .keep),
            volume("mssql2025-data", .keep))

        #expect(!cli.calls.contains { $0.first == "rmi" || $0.first == "volume" })
        #expect(result.report.itemsFailed == 2)
        #expect(result.report.errors.allSatisfy { $0.message.contains("KEEP") })
    }

    // Solo Swift: la guardia sul KEEP vale per ogni tipo, anche per la cache di build, che non ha
    // altre guardie sull'ID: senza questo controllo `builder prune -f` partirebbe comunque.
    @Test func keepBuildCacheIsRefusedWithoutPruning() async throws {
        let cli = succeedingCli()
        let keptCache = DockerCandidate(
            kind: .buildCache, id: DockerClassifier.buildCacheId, displayName: "Cache di build", sizeBytes: 1_000,
            verdict: .keep, ruleId: "build-cache", reason: "m", cost: "c")

        let result = try await execute(cli, keptCache)

        #expect(!cli.calls.contains { $0.first == "builder" })
        #expect(result.report.itemsDeleted == 0)
        #expect(result.report.itemsFailed == 1)
        #expect(result.report.errors.allSatisfy { $0.message.contains("KEEP") })
    }

    @Test(arguments: ["testcontainers/ryuk:0.14.0", "sha256:abc", "-f"])
    func imageIdentifiersThatAreNotFullIdsAreRefused(id: String) async throws {
        let cli = succeedingCli()

        let result = try await execute(cli, image(id, id))

        #expect(!cli.calls.contains { $0.first == "rmi" })
        #expect(result.report.itemsFailed == 1)
    }

    @Test(arguments: ["-f", "--all", ""])
    func volumeNamesThatLookLikeFlagsAreRefused(name: String) async throws {
        let cli = succeedingCli()

        let result = try await execute(cli, volume(name))

        #expect(!cli.calls.contains { $0.first == "volume" })
        #expect(result.report.itemsFailed == 1)
    }

    // Solo Swift: le guardie sugli ID tengono il `$` stretto di Swift, che vale solo alla fine del
    // testo. Il `$` di .NET accetterebbe un "\n" finale (la tabella delle convenzioni lo traduce in
    // `\n?$` ovunque tranne qui): un ID con il "\n" non è né un `sha256:` di 64 cifre né un nome di
    // volume valido, e non deve arrivare a `rmi` o a `volume rm`.
    @Test func identifiersWithATrailingNewlineAreRefused() async throws {
        let cli = succeedingCli()

        let result = try await execute(cli,
            image(Self.ryukId + "\n", "ryuk"),
            volume("old-data\n"))

        #expect(!cli.calls.contains { $0.first == "rmi" || $0.first == "volume" })
        #expect(result.report.itemsDeleted == 0)
        #expect(result.report.itemsFailed == 2)
        #expect(result.report.errors.map(\.path) == ["ryuk", "old-data\n"])
    }

    @Test func refusedImageIsReportedWithDockersReason() async throws {
        let cli = succeedingCli()
            .onPrefix("rmi \(DockerFixtures.alpineId)") { _ in
                FakeDockerCli.fail("Error response from daemon: conflict: unable to delete d4d4d4d4d4d4 (must be forced) - image is referenced in multiple repositories")
            }

        let result = try await execute(cli, image(DockerFixtures.alpineId, "alpine:3.20"), image(Self.ryukId, "ryuk"))

        let error = try #require(result.report.errors.first)
        #expect(result.report.errors.count == 1)
        #expect(error.path == "alpine:3.20")
        #expect(error.message.contains("referenced in multiple repositories"))
        #expect(result.report.itemsDeleted == 1)
    }

    @Test func imageWithDependentChildrenIsRetriedAfterTheOthers() async throws {
        let baseAttempts = Shared(0)
        let childDeleted = Shared(false)
        let cli = succeedingCli()
            .on("rmi \(DockerFixtures.azureLinuxId)") {
                baseAttempts.increment() == 1 && !childDeleted.value
                    ? FakeDockerCli.fail("Error response from daemon: conflict: unable to delete 34a22db497ff (cannot be forced) - image has dependent child images")
                    : FakeDockerCli.ok("Deleted")
            }
            .on("rmi \(DockerFixtures.dcptunId)") {
                childDeleted.set(true)
                return FakeDockerCli.ok("Deleted")
            }

        let result = try await execute(cli,
            image(DockerFixtures.azureLinuxId, "azurelinux/base/core:3.0"),
            image(DockerFixtures.dcptunId, "dcptun_developer_ms:0.25.13"))

        #expect(baseAttempts.value == 2)
        #expect(result.report.itemsDeleted == 2)
        #expect(result.report.errors.isEmpty)
    }

    @Test func daemonLostMidwayStopsAndReportsWhatIsLeft() async throws {
        let cli = succeedingCli()
            .on("rmi \(DockerFixtures.alpineId)") { throw DockerUnavailableError(DockerUnavailableError.notRunning) }

        let result = try await execute(cli,
            image(Self.ryukId, "ryuk"),
            image(DockerFixtures.alpineId, "alpine:3.20"),
            volume("old-data"))

        #expect(result.daemonLost)
        #expect(result.report.itemsDeleted == 1)
        #expect(result.report.itemsFailed == 2)
        #expect(!cli.commandLines.contains("volume rm old-data"))
        #expect(result.after == nil)
        #expect(result.report.errors.allSatisfy { $0.message.contains("Docker") })
    }

    @Test func daemonLostDuringARetryStillAccountsForEveryItem() async throws {
        // La base fallisce per le immagini figlie; al ritentativo il daemon è sparito.
        let attempts = Shared(0)
        let cli = succeedingCli()
            .on("rmi \(DockerFixtures.azureLinuxId)") {
                guard attempts.increment() == 1 else { throw DockerUnavailableError(DockerUnavailableError.notRunning) }
                return FakeDockerCli.fail("conflict: image has dependent child images")
            }

        let result = try await execute(cli,
            image(DockerFixtures.azureLinuxId, "azurelinux"),
            image(DockerFixtures.dcptunId, "dcptun"),
            volume("old-data"),
            Self.buildCache)

        #expect(result.report.itemsDeleted == 1)
        #expect(result.report.errors.map(\.path) == ["azurelinux", "old-data", "Cache di build"])
    }

    @Test func bytesFreedAreTheSystemDfDeltaPerType() async throws {
        let result = try await execute(succeedingCli(), image(Self.ryukId, "ryuk"), volume("old-data"), Self.buildCache)

        #expect(result.report.categories.first { $0.categoryId == DockerCategories.images }?.bytesFreed == 340_000_000)
        #expect(result.report.categories.first { $0.categoryId == DockerCategories.volumes }?.bytesFreed == 88_500_000)
        #expect(result.report.categories.first { $0.categoryId == DockerCategories.buildCache }?.bytesFreed == 106_900_000)
        #expect(result.report.bytesFreed == Int64(340_000_000 + 88_500_000 + 106_900_000))
    }

    @Test func categoriesWithoutDeletionsGetNoBytes() async throws {
        // Solo un volume cancellato: se nel frattempo un'immagine sparisce per altri motivi, quel
        // delta non va attribuito a questa pulizia.
        let result = try await execute(succeedingCli(), volume("old-data"))

        #expect(result.report.categories.map(\.categoryId) == [DockerCategories.volumes])
        #expect(result.report.bytesFreed == 88_500_000)
    }

    @Test func deletedResourcesAreLoggedWithTheirIdentity() async throws {
        let result = try await execute(succeedingCli(), image(Self.ryukId, "testcontainers/ryuk:0.14.0"), volume("old-data"), Self.buildCache)

        #expect(result.report.deletedPaths == [
            "docker:image:\(Self.ryukId) (testcontainers/ryuk:0.14.0)",
            "docker:volume:old-data",
            "docker:build-cache",
        ])
    }

    // Il C# annullava il token dentro la risposta di `rmi`; qui il comando gira isolato
    // dall'annullamento (come con `CancellationToken.None`), quindi si annulla il task dell'esecutore
    // dal callback di avanzamento, che arriva subito dopo la stessa cancellazione.
    @Test func cancellationReturnsAPartialReport() async throws {
        let cli = succeedingCli()
        let executor = executor(cli)
        let selected = [image(Self.ryukId, "ryuk"), image(DockerFixtures.alpineId, "alpine")]

        let result = try await Task {
            try await executor.execute(selected, on: Self.target, progress: { _ in cancelCurrentTask() })
        }.value

        #expect(result.report.itemsDeleted == 1)
        #expect(!cli.commandLines.contains("rmi \(DockerFixtures.alpineId)"))
    }

    @Test func progressIsReportedForEveryItem() async throws {
        let reports = Recorder<CleanProgress>()

        _ = try await executor(succeedingCli()).execute([image(Self.ryukId, "ryuk"), volume("old-data")], on: Self.target, progress: reports.append)

        #expect(reports.values.map(\.itemsDone) == [1, 2])
    }

    // Solo Swift: la misura finale usa `CancellationToken.None` nel C#; qui il comando gira in un
    // task che non eredita l'annullamento, e la CLI finta, come `ProcessRunner`, rifiuterebbe di
    // avviarlo da un task annullato.
    @Test func cancelledCleanupStillMeasuresAfterwards() async throws {
        let executor = executor(succeedingCli())
        let selected = [image(Self.ryukId, "ryuk"), volume("old-data")]

        let result = try await Task {
            try await executor.execute(selected, on: Self.target, progress: { _ in cancelCurrentTask() })
        }.value

        #expect(result.report.itemsDeleted == 1)
        #expect(result.after != nil)
        #expect(result.report.bytesFreed == 340_000_000)
    }

    // Solo Swift: le due prove sopra annullano dal callback, cioè dopo che il comando è già tornato.
    // Qui l'annullamento arriva mentre `rmi` è in corso: come `ProcessRunner`, il comando controlla
    // l'annullamento solo dopo la risposta (`CancellationCheckingCli`), quindi senza l'isolamento
    // dell'esecutore la cancellazione fallirebbe e il resoconto andrebbe perso.
    @Test func cancellationDuringADeletionDoesNotInterruptIt() async throws {
        let outer = Shared<Task<DockerCleanResult, any Error>?>(nil)
        let cli = succeedingCli()
            .on("rmi \(Self.ryukId)") {
                outer.value?.cancel()
                return FakeDockerCli.ok("Deleted")
            }
        let executor = DockerCleanExecutor(
            cli: CancellationCheckingCli(inner: Self.contexts(cli)),
            clock: FixedWallClock(now: Date(timeIntervalSince1970: 0)))
        let selected = [image(Self.ryukId, "ryuk"), image(DockerFixtures.alpineId, "alpine")]
        let (gate, open) = AsyncStream<Void>.makeStream()

        // Il task attende il via prima di chiamare l'esecutore, così il riferimento è già salvato
        // quando parte il primo `rmi`.
        let task = Task<DockerCleanResult, any Error> {
            for await _ in gate { break }
            return try await executor.execute(selected, on: Self.target, progress: nil)
        }
        outer.set(task)
        open.yield(())
        open.finish()

        let result = try await task.value

        #expect(result.report.itemsDeleted == 1)
        #expect(result.report.deletedPaths == ["docker:image:\(Self.ryukId) (ryuk)"])
        #expect(!cli.commandLines.contains("rmi \(DockerFixtures.alpineId)"))
        #expect(result.after != nil)
    }

    /// Il contesto attivo è `orbstack`: ogni comando va comunque a `desktop-linux`, e prima della
    /// misura iniziale si legge il motore.
    @Test func everyCommandGoesToTheContextOfTheAnalysis() async throws {
        let cli = succeedingCli()
        let orbStack = FakeDockerCli()
        let docker = Self.contexts(cli, orbStack: orbStack)
        let executor = DockerCleanExecutor(cli: docker, clock: FixedWallClock(now: Date(timeIntervalSince1970: 0)))

        let result = try await executor.execute(
            [image(Self.ryukId, "ryuk"), volume("old-data"), Self.buildCache], on: Self.target, progress: nil)

        #expect(result.report.itemsDeleted == 3)
        #expect(docker.calls.allSatisfy { $0.starts(with: ["--context", "desktop-linux"]) })
        #expect(cli.commandLines.prefix(2) == ["info --format \(DockerInventoryCollector.engineFormat)", "system df --format {{json .}}"])
        #expect(orbStack.calls.isEmpty)
    }

    /// Lo stesso contesto ma un altro daemon: `default` riscritto da un altro motore, un motore
    /// aggiornato o sostituito. Dopo `docker info` non parte nessun comando.
    @Test(arguments: [
        ("9a8b7c6d-other", "29.8.0", "Docker Desktop"),
        ("5f0d6c1e-desktop", "29.9.0", "Docker Desktop"),
        ("5f0d6c1e-desktop", "29.8.0", "OrbStack"),
    ])
    func anotherDaemonBehindTheSameContextDeletesNothing(id: String, version: String, operatingSystem: String) async throws {
        let cli = succeedingCli().on(FakeDockerCli.infoCommand, FakeDockerCli.info(version, operatingSystem, id: id))

        let error = await #expect(throws: DockerEngineChangedError.self) {
            try await execute(cli, image(Self.ryukId, "ryuk"), volume("old-data"), Self.buildCache)
        }

        #expect(error == DockerEngineChangedError(context: "desktop-linux"))
        #expect(error?.message == "Il motore Docker del contesto «desktop-linux» non è più quello analizzato: non è stato eliminato nulla. Premi Riprova per analizzarlo di nuovo.")
        #expect(cli.commandLines == ["info --format \(DockerInventoryCollector.engineFormat)"])
    }

    @Test func aTargetWithAnInvalidContextNameDeletesNothing() async throws {
        let cli = succeedingCli()
        let docker = Self.contexts(cli)
        let executor = DockerCleanExecutor(cli: docker, clock: FixedWallClock(now: Date(timeIntervalSince1970: 0)))
        let target = DockerTarget(
            context: DockerContext(name: "--host=tcp://10.0.0.1:2375", description: "", host: ""),
            engine: Self.target.engine)

        await #expect(throws: DockerOutputError("Nome del contesto Docker non valido: «--host=tcp://10.0.0.1:2375».")) {
            try await executor.execute([volume("old-data")], on: target, progress: nil)
        }
        #expect(docker.calls.isEmpty)
    }
}

/// Come `ProcessRunner`: il comando risponde e solo dopo controlla l'annullamento del task che lo
/// attende (il processo reale viene ucciso da `onCancel`, e il suo esito si riconosce dopo l'uscita).
/// `FakeDockerCli` controlla invece solo prima di rispondere.
private struct CancellationCheckingCli: DockerCommandRunning {
    let inner: any DockerCommandRunning

    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
        let result = try await inner.run(arguments, timeout: timeout)
        try Task.checkCancellation()
        return result
    }
}
