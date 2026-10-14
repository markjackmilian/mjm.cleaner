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

    private static let buildCache = DockerCandidate(
        kind: .buildCache, id: DockerClassifier.buildCacheId, displayName: "Cache di build", sizeBytes: 1_000,
        verdict: .delete, ruleId: "build-cache", reason: "m", cost: "c")

    private func image(_ id: String, _ name: String, _ verdict: DockerVerdict = .delete) -> DockerCandidate {
        DockerCandidate(kind: .image, id: id, displayName: name, sizeBytes: 1_000, verdict: verdict, ruleId: "rule", reason: "motivo", cost: "costo")
    }

    private func volume(_ name: String, _ verdict: DockerVerdict = .propose) -> DockerCandidate {
        DockerCandidate(kind: .volume, id: name, displayName: name, sizeBytes: 1_000, verdict: verdict, ruleId: "rule", reason: "motivo", cost: "costo")
    }

    /// CLI che accetta ogni cancellazione e restituisce il df prima e dopo.
    private func succeedingCli() -> FakeDockerCli {
        let dfCalls = Shared(0)
        return FakeDockerCli()
            .on("system df --format {{json .}}") { FakeDockerCli.ok(dfCalls.increment() == 1 ? Self.dfBefore : Self.dfAfter) }
            .onPrefix("rmi ") { _ in FakeDockerCli.ok("Deleted") }
            .onPrefix("volume rm ") { arguments in FakeDockerCli.ok(arguments.last ?? "") }
            .on("builder prune -f", "Total reclaimed space: 106.9MB")
    }

    private func executor(_ cli: FakeDockerCli) -> DockerCleanExecutor {
        DockerCleanExecutor(cli: cli, clock: FixedWallClock(now: Date(timeIntervalSince1970: 0)))
    }

    private func execute(_ cli: FakeDockerCli, _ selected: DockerCandidate...) async throws -> DockerCleanResult {
        try await executor(cli).execute(selected, progress: nil)
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
            try await executor.execute(selected, progress: { _ in cancelCurrentTask() })
        }.value

        #expect(result.report.itemsDeleted == 1)
        #expect(!cli.commandLines.contains("rmi \(DockerFixtures.alpineId)"))
    }

    @Test func progressIsReportedForEveryItem() async throws {
        let reports = Recorder<CleanProgress>()

        _ = try await executor(succeedingCli()).execute([image(Self.ryukId, "ryuk"), volume("old-data")], progress: reports.append)

        #expect(reports.values.map(\.itemsDone) == [1, 2])
    }

    // Solo Swift: la misura finale usa `CancellationToken.None` nel C#; qui il comando gira in un
    // task che non eredita l'annullamento, e la CLI finta, come `ProcessRunner`, rifiuterebbe di
    // avviarlo da un task annullato.
    @Test func cancelledCleanupStillMeasuresAfterwards() async throws {
        let executor = executor(succeedingCli())
        let selected = [image(Self.ryukId, "ryuk"), volume("old-data")]

        let result = try await Task {
            try await executor.execute(selected, progress: { _ in cancelCurrentTask() })
        }.value

        #expect(result.report.itemsDeleted == 1)
        #expect(result.after != nil)
        #expect(result.report.bytesFreed == 340_000_000)
    }
}
