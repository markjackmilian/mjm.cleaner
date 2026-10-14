import Foundation
import Synchronization
import Testing
@testable import CleanerCore

struct XcodeCleanExecutorTests {
    private static let deviceId = "11111111-1111-4111-8111-111111111111"
    private static let otherDeviceId = "33333333-3333-4333-8333-333333333333"
    private static let runtimeId = "22222222-2222-4222-8222-222222222222"
    private static let success = ProcessResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: false)

    // MARK: - Doppi

    /// Porting di `QueueCollector`: restituisce gli inventari in ordine, poi ripete l'ultimo.
    private final class QueueCollector: XcodeInventoryCollecting {
        private let snapshots: [XcodeSnapshot]
        private let index = Mutex(0)

        init(_ snapshots: XcodeSnapshot...) {
            self.snapshots = snapshots
        }

        func collect() async throws -> XcodeSnapshot {
            let position = index.withLock { value in
                defer { value += 1 }
                return min(value, snapshots.count - 1)
            }
            return snapshots[position]
        }
    }

    private struct FakeCli: XcodeCliInvoking {
        let deletedDevices = Recorder<String>()
        let operationOrder = Recorder<String>()
        let deletedRuntimes = Recorder<String>()
        var deviceResult = XcodeCleanExecutorTests.success
        var deviceResultForSecond = XcodeCleanExecutorTests.success
        var onDeviceDelete: (@Sendable (String) -> Void)?
        var deviceError: (any Error)?

        func readInventory() async throws -> XcodeSnapshot { .empty }

        func deleteDevice(_ uuid: String) async throws -> ProcessResult {
            deletedDevices.append(uuid)
            operationOrder.append("device")
            onDeviceDelete?(uuid)
            if let deviceError { throw deviceError }
            return deletedDevices.values.count == 1 ? deviceResult : deviceResultForSecond
        }

        func deleteRuntime(_ uuid: String) async throws -> ProcessResult {
            operationOrder.append("runtime")
            deletedRuntimes.append(uuid)
            return XcodeCleanExecutorTests.success
        }
    }

    /// Porting di `FakeCleanEngine`. Con `journals` registra nel diario ogni elemento ricevuto,
    /// come fa `CleanEngine` per ciò che elimina.
    private struct FakeCleanEngine: CleanPerforming {
        let calls = Recorder<[CategorySelection]>()
        var bytesFreed: Int64 = 0
        var itemsDeleted = 0
        var journals = false

        func clean(_ selections: [CategorySelection], progress: (@Sendable (CleanProgress) -> Void)?, journal: (any DeletionRecording)?) async -> CleanReport {
            calls.append(selections)
            if journals {
                for item in selections.flatMap(\.items) { journal?.recordDeleted(item.path) }
            }
            return CleanReport(startedAt: Date(timeIntervalSince1970: 0), duration: .zero, bytesFreed: bytesFreed,
                               itemsDeleted: itemsDeleted, itemsFailed: 0, categories: [], errors: [], deletedPaths: [])
        }
    }

    private struct FakeSizeProbe: XcodeSizeProbing {
        func measure(_ path: String) async throws -> Int64? { nil }
        func freeBytes() async throws -> Int64? { 1000 }
    }

    private final class QueueRunningProbe: XcodeRunningProbing {
        private let states: [XcodeRunningState]
        private let index = Mutex(0)

        init(_ states: XcodeRunningState...) {
            self.states = states
        }

        func state() async throws -> XcodeRunningState {
            let position = index.withLock { value in
                defer { value += 1 }
                return min(value, states.count - 1)
            }
            return states[position]
        }
    }

    private struct JournalRecorder: DeletionRecording {
        let paths = Recorder<String>()

        func recordDeleted(_ path: String) {
            paths.append(path)
        }
    }

    // MARK: - Costruzione

    private func create(_ cli: FakeCli, _ collector: any XcodeInventoryCollecting, _ clean: FakeCleanEngine = FakeCleanEngine()) -> XcodeCleanExecutor {
        XcodeCleanExecutor(cli: cli, collector: collector, cleanEngine: clean, measures: FakeSizeProbe(),
                           runningProbe: QueueRunningProbe(.notRunning), clock: SystemWallClock())
    }

    private func snapshot(_ candidates: XcodeCandidate...) -> XcodeSnapshot {
        XcodeSnapshot(candidates: candidates, warnings: [])
    }

    private func snapshot(_ candidates: [XcodeCandidate], _ warnings: XcodeInventoryWarning...) -> XcodeSnapshot {
        XcodeSnapshot(candidates: candidates, warnings: warnings)
    }

    private func device(_ id: String = Self.deviceId, size: Int64? = 100) -> XcodeCandidate {
        XcodeCandidate(key: id, kind: .device, name: "iPhone", cliId: id, build: "build-1", state: "Shutdown", sizeBytes: size)
    }

    private func runtime(_ dependencies: [String]) -> XcodeCandidate {
        XcodeCandidate(key: "runtime:" + Self.runtimeId, kind: .runtime, name: "iOS 18", cliId: Self.runtimeId,
                       runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0", build: "runtime-build", sizeBytes: 200,
                       dependencies: dependencies)
    }

    private func confirm(_ source: XcodeSnapshot, _ selected: String...) throws -> XcodeConfirmedPlan {
        try XcodeSelection.confirm(XcodeSelection.preview(source, selectedKeys: Set(selected)), acknowledgeDependencies: true)
    }

    private func parseUnavailableDevice(includeRuntime: Bool = false) -> XcodeSnapshot {
        let simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Unavailable"}]},
             "runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18","version":"18.0","buildversion":"22A3351","platform":"iOS"}]}
            """
        let images = """
            {"22222222-2222-4222-8222-222222222222":{"identifier":"22222222-2222-4222-8222-222222222222","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A3351","deletable":true}}
            """
        return XcodeJson.parseInventory(simctl, includeRuntime ? images : "{}", runtimeDeleteSupported: true)
    }

    private static let derivedDataRoot = "/Users/test/Library/Developer/Xcode/DerivedData"
    private static let appPath = derivedDataRoot + "/App-abc"
    private static let appKey = "derived-data:" + appPath

    /// Una cartella DerivedData con identità completa. I parametri opzionali alterano soltanto la
    /// riga candidata o il percorso catturato nell'identità: servono ai test di rivalidazione.
    private func folderSnapshot(
        path: String = Self.appPath,
        candidatePath: String? = nil,
        identityPath: String? = nil,
        allocatedBytes: Int64?,
        logicalBytes: Int64 = 10 * 1024 * 1024 * 1024
    ) -> XcodeSnapshot {
        let key = "derived-data:" + path
        let scan = ScanItem(path: path, sizeBytes: logicalBytes, isDirectory: true, declaredRoot: Self.derivedDataRoot)
        let identity = XcodeFileIdentity(canonicalPath: identityPath ?? path, isDirectory: true, creationTime: Date(timeIntervalSince1970: 86_400),
                                         lastWriteTime: Date(timeIntervalSince1970: 2 * 86_400), logicalSizeBytes: logicalBytes)
        return XcodeSnapshot(
            candidates: [XcodeCandidate(key: key, kind: .derivedData, name: "App-abc", path: candidatePath ?? path, sizeBytes: allocatedBytes)],
            warnings: [],
            fileInventory: XcodeFileInventory([(key, XcodeFileEntry(item: scan, identity: identity))]))
    }

    /// `FileSnapshot` del C#: una cartella DerivedData con identità completa.
    private func fileSnapshot(allocatedBytes: Int64?, logicalBytes: Int64 = 10 * 1024 * 1024 * 1024) -> XcodeSnapshot {
        folderSnapshot(allocatedBytes: allocatedBytes, logicalBytes: logicalBytes)
    }

    private func single(_ result: XcodeCleanResult) throws -> XcodeItemResult {
        #expect(result.items.count == 1)
        return try #require(result.items.first)
    }

    // MARK: - Test portati

    @Test func revalidationNeverAddsItems() async throws {
        let plan = try confirm(snapshot(device(), runtime([Self.deviceId])), Self.deviceId)
        let cli = FakeCli()
        let clean = FakeCleanEngine()
        let executor = create(cli, QueueCollector(snapshot(device(), device(Self.otherDeviceId)), snapshot(device(Self.otherDeviceId))), clean)

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedDevices.values == [Self.deviceId])
        #expect(clean.calls.values.isEmpty)
        #expect(try single(result).outcome == .deleted)
    }

    @Test func changedIdentityIsSkipped() async throws {
        let plan = try confirm(snapshot(device()), Self.deviceId)
        let cli = FakeCli()
        var rebuilt = device()
        rebuilt.build = "new-build"

        let result = await create(cli, QueueCollector(snapshot(rebuilt))).execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedDevices.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
    }

    @Test func deviceBootedAfterConfirmationIsSkipped() async throws {
        let plan = try confirm(snapshot(device()), Self.deviceId)
        let cli = FakeCli()
        var booted = device()
        booted.state = "Booted"

        let result = await create(cli, QueueCollector(snapshot(booted))).execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedDevices.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
    }

    @Test func devicesRunBeforeRuntimes() async throws {
        let plan = try confirm(snapshot(device(), runtime([Self.deviceId])), Self.deviceId, "runtime:" + Self.runtimeId)
        let cli = FakeCli()
        let clean = FakeCleanEngine()
        let executor = create(cli, QueueCollector(
            snapshot(device(), runtime([Self.deviceId])),
            snapshot(runtime([])),
            snapshot(runtime([])),
            snapshot()), clean)

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values == ["device", "runtime"])
        #expect(result.items.allSatisfy { $0.outcome == .deleted })
        #expect(clean.calls.values.isEmpty)
    }

    @Test func deviceFailureSkipsDependentRuntime() async throws {
        let plan = try confirm(snapshot(device(), runtime([Self.deviceId])), Self.deviceId, "runtime:" + Self.runtimeId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 1, standardOutput: "", standardError: "in use", timedOut: false)

        let result = await create(cli, QueueCollector(snapshot(device(), runtime([Self.deviceId])))).execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values == ["device"])
        #expect(result.items.map(\.outcome) == [.failed, .skipped])
    }

    @Test func newRuntimeDependencyAfterConfirmationSkipsRuntime() async throws {
        let plan = try confirm(snapshot(device(), runtime([Self.deviceId])), "runtime:" + Self.runtimeId)
        let cli = FakeCli()

        let result = await create(cli, QueueCollector(snapshot(device(), device(Self.otherDeviceId), runtime([Self.deviceId, Self.otherDeviceId]))))
            .execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
    }

    @Test func timeoutWithUnreadableInventoryIsUncertain() async throws {
        let plan = try confirm(snapshot(device()), Self.deviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true)
        let collector = QueueCollector(snapshot(device()), snapshot([], XcodeInventoryWarning(resourceGroup: .device, message: "unavailable")))

        let result = await create(cli, collector).execute(plan, progress: nil, journal: nil)

        #expect(try single(result).outcome == .uncertain)
        #expect(cli.deletedDevices.values.count == 1)
    }

    @Test func incompletePostCommandInventoryCannotVerifyAbsence() async throws {
        let malformedSimctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"33333333-3333-4333-8333-333333333333","name":"iPhone 16","state":"Shutdown","dataPathSize":[]},
              {"name":"missing UUID","state":"Shutdown"}]}}
            """
        let incomplete = XcodeJson.parseInventory(malformedSimctl, "{}", runtimeDeleteSupported: true)
        let plan = try confirm(snapshot(device(size: 500)), Self.deviceId)
        let cli = FakeCli()
        let clean = FakeCleanEngine()

        let result = await create(cli, QueueCollector(snapshot(device(size: 500)), incomplete), clean).execute(plan, progress: nil, journal: nil)

        #expect(!incomplete.candidates.contains { $0.key == Self.deviceId })
        #expect(try single(result).outcome == .uncertain)
        #expect(result.historyReport.bytesFreed == 0)
        #expect(cli.deletedDevices.values.count == 1)
        #expect(clean.calls.values.isEmpty)
    }

    @Test func failedCommandAndAbsentResourceIsNotCredited() async throws {
        let plan = try confirm(snapshot(device(size: 500)), Self.deviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 1, standardOutput: "", standardError: "failed", timedOut: false)
        let clean = FakeCleanEngine()

        let result = await create(cli, QueueCollector(snapshot(device(size: 500)), snapshot()), clean).execute(plan, progress: nil, journal: nil)

        #expect(try single(result).outcome == .failed)
        #expect(result.historyReport.bytesFreed == 0)
        #expect(clean.calls.values.isEmpty)
    }

    @Test func timedOutCommandAndAbsentResourceIsUncertainWithoutCredit() async throws {
        let plan = try confirm(snapshot(device(size: 500)), Self.deviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: true)
        let clean = FakeCleanEngine()

        let result = await create(cli, QueueCollector(snapshot(device(size: 500)), snapshot()), clean).execute(plan, progress: nil, journal: nil)

        #expect(try single(result).outcome == .uncertain)
        #expect(result.historyReport.bytesFreed == 0)
        #expect(clean.calls.values.isEmpty)
    }

    @Test func cancelledCommandAndAbsentResourceIsUncertainWithoutCredit() async throws {
        let plan = try confirm(snapshot(device(size: 500)), Self.deviceId)
        var cli = FakeCli()
        cli.onDeviceDelete = { _ in cancelCurrentTask() }
        let executor = create(cli, QueueCollector(snapshot(device(size: 500)), snapshot()))

        let result = await Task { await executor.execute(plan, progress: nil, journal: nil) }.value

        #expect(try single(result).outcome == .uncertain)
        #expect(result.historyReport.bytesFreed == 0)
    }

    @Test func commandExceptionAndAbsentResourceIsNotCredited() async throws {
        let plan = try confirm(snapshot(device(size: 500)), Self.deviceId)
        var cli = FakeCli()
        cli.deviceError = UnexpectedTestError(description: "runner failed")

        let result = await create(cli, QueueCollector(snapshot(device(size: 500)), snapshot())).execute(plan, progress: nil, journal: nil)

        let item = try single(result)
        #expect(item.outcome == .failed)
        #expect(item.reason == "runner failed")
        #expect(result.historyReport.bytesFreed == 0)
    }

    @Test func advisoryRuntimeSizeWarningDoesNotBlockDeleteOrVerification() async throws {
        let plan = try confirm(snapshot(runtime([])), "runtime:" + Self.runtimeId)
        let advisory = XcodeInventoryWarning(resourceGroup: .runtime, message: "runtime size unknown", kind: .advisory)
        let cli = FakeCli()
        let clean = FakeCleanEngine()
        let executor = create(cli, QueueCollector(snapshot([runtime([])], advisory), snapshot([], advisory)), clean)

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values == ["runtime"])
        #expect(try single(result).outcome == .deleted)
        #expect(result.historyReport.bytesFreed == 200)
        #expect(clean.calls.values.isEmpty)
    }

    @Test func completenessWarningStillBlocksRuntimeDelete() async throws {
        let plan = try confirm(snapshot(runtime([])), "runtime:" + Self.runtimeId)
        let cli = FakeCli()
        let clean = FakeCleanEngine()
        let incomplete = XcodeInventoryWarning(resourceGroup: .runtime, message: "runtime inventory incomplete")
        let executor = create(cli, QueueCollector(snapshot([runtime([])], incomplete)), clean)

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
        #expect(clean.calls.values.isEmpty)
    }

    @Test func cancellationRetainsCompletedResults() async throws {
        let cli = FakeCli()
        let plan = try confirm(snapshot(device(), device(Self.otherDeviceId)), Self.deviceId, Self.otherDeviceId)
        let executor = create(cli, QueueCollector(snapshot(device(), device(Self.otherDeviceId)), snapshot(device(Self.otherDeviceId))))

        let result = await Task {
            await executor.execute(plan, progress: { if $0.itemsDone == 1 { cancelCurrentTask() } }, journal: nil)
        }.value

        #expect(result.items.map(\.outcome) == [.deleted, .skipped])
        #expect(cli.deletedDevices.values.count == 1)
    }

    @Test func failedAndUnknownSizesDoNotIncreaseHistoryBytes() async throws {
        let unknown = device(Self.otherDeviceId, size: nil)
        let plan = try confirm(snapshot(device(size: 500), unknown), Self.deviceId, Self.otherDeviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 1, standardOutput: "", standardError: "failure", timedOut: false)

        let result = await create(cli, QueueCollector(
            snapshot(device(size: 500), unknown), snapshot(device(size: 500), unknown),
            snapshot(device(size: 500), unknown), snapshot(unknown))).execute(plan, progress: nil, journal: nil)

        #expect(result.historyReport.bytesFreed == 0)
        #expect(result.items.first?.verifiedEstimatedBytes == nil)
    }

    @Test func independentFailureDoesNotStopOtherItems() async throws {
        let plan = try confirm(snapshot(device(), device(Self.otherDeviceId)), Self.deviceId, Self.otherDeviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 1, standardOutput: "", standardError: "failure", timedOut: false)
        let executor = create(cli, QueueCollector(
            snapshot(device(), device(Self.otherDeviceId)), snapshot(device(), device(Self.otherDeviceId)),
            snapshot(device(), device(Self.otherDeviceId)), snapshot(device())))

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedDevices.values == [Self.deviceId, Self.otherDeviceId])
        #expect(result.items.map(\.outcome) == [.failed, .deleted])
    }

    @Test func xcodeStartedAfterConfirmationBlocksFilesWithoutCallingCleanEngine() async throws {
        let source = fileSnapshot(allocatedBytes: 10, logicalBytes: 50)
        let plan = try confirm(source, Self.appKey)
        let cli = FakeCli()
        let clean = FakeCleanEngine()
        let executor = XcodeCleanExecutor(cli: cli, collector: QueueCollector(source), cleanEngine: clean, measures: FakeSizeProbe(),
                                          runningProbe: QueueRunningProbe(.running), clock: SystemWallClock())

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(clean.calls.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
        #expect(cli.deletedDevices.values.isEmpty)
    }

    @Test func parsedUnavailableDeviceCanBeDeletedThroughExecutor() async throws {
        let unavailable = parseUnavailableDevice()
        let plan = try confirm(unavailable, Self.deviceId)
        let cli = FakeCli()
        let after = XcodeJson.parseInventory(#"{"runtimes":[],"devices":{}}"#, "{}", runtimeDeleteSupported: true)

        let result = await create(cli, QueueCollector(unavailable, after)).execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedDevices.values == [Self.deviceId])
        #expect(try single(result).outcome == .deleted)
    }

    @Test func parsedUnavailableDependencyDoesNotBlockRuntimeDelete() async throws {
        let unavailable = parseUnavailableDevice(includeRuntime: true)
        let plan = try confirm(unavailable, "runtime:" + Self.runtimeId)
        let cli = FakeCli()
        let after = XcodeJson.parseInventory(#"{"runtimes":[],"devices":{}}"#, "{}", runtimeDeleteSupported: true)

        let result = await create(cli, QueueCollector(unavailable, after)).execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values == ["runtime"])
        #expect(try single(result).outcome == .deleted)
    }

    @Test func parsedUnknownDeviceStateRemainsBlockedAtExecutor() {
        let simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"MysteryState"}]}}
            """
        let unknown = XcodeJson.parseInventory(simctl, "{}", runtimeDeleteSupported: true)
        let cli = FakeCli()

        #expect(throws: XcodeArgumentError.self) { try confirm(unknown, Self.deviceId) }
        #expect(cli.deletedDevices.values.isEmpty)
    }

    @Test func fileHistoryUsesFreshAllocatedSizeInsteadOfLogicalBytesFreed() async throws {
        let allocatedBytes: Int64 = 1_048_576
        let plan = try confirm(fileSnapshot(allocatedBytes: 4_194_304), Self.appKey)
        let clean = FakeCleanEngine(bytesFreed: 10 * 1024 * 1024 * 1024, itemsDeleted: 1)

        let result = await create(FakeCli(), QueueCollector(fileSnapshot(allocatedBytes: allocatedBytes)), clean).execute(plan, progress: nil, journal: nil)

        #expect(try single(result).verifiedEstimatedBytes == allocatedBytes)
        #expect(result.historyReport.bytesFreed == allocatedBytes)
    }

    @Test func fileHistoryLeavesSizeUnknownWhenFreshAllocatedMeasureIsUnavailable() async throws {
        let plan = try confirm(fileSnapshot(allocatedBytes: 4_194_304), Self.appKey)
        let clean = FakeCleanEngine(bytesFreed: 10 * 1024 * 1024 * 1024, itemsDeleted: 1)

        let result = await create(FakeCli(), QueueCollector(fileSnapshot(allocatedBytes: nil)), clean).execute(plan, progress: nil, journal: nil)

        #expect(try single(result).verifiedEstimatedBytes == nil)
        #expect(result.historyReport.bytesFreed == 0)
    }

    // MARK: - Solo Swift: diario della pulizia (spec §8.2)

    // Le cartelle arrivano al diario tramite CleanEngine, che riceve lo stesso journal; i
    // simulatori rimossi con verifica vi entrano con il testo che lo storico registra (la chiave,
    // perché un simulatore non ha percorso). Un comando fallito non vi entra mai.
    @Test func journalReceivesVerifiedCliDeletionsAndIsForwardedToTheCleanEngine() async throws {
        var files = fileSnapshot(allocatedBytes: 10, logicalBytes: 50)
        let both = XcodeSnapshot(candidates: [device(), device(Self.otherDeviceId)] + files.candidates, warnings: [], fileInventory: files.fileInventory)
        files.candidates.append(device(Self.otherDeviceId))
        let plan = try confirm(both, Self.deviceId, Self.otherDeviceId, Self.appKey)
        var cli = FakeCli()
        cli.deviceResultForSecond = ProcessResult(exitCode: 1, standardOutput: "", standardError: "in use", timedOut: false)
        let clean = FakeCleanEngine(itemsDeleted: 1, journals: true)
        let journal = JournalRecorder()

        let result = await create(cli, QueueCollector(both, files), clean).execute(plan, progress: nil, journal: journal)

        #expect(result.items.map(\.outcome) == [.deleted, .failed, .deleted])
        #expect(journal.paths.values == [Self.deviceId, Self.appPath])
        #expect(clean.calls.values.flatMap { $0.map(\.categoryId) } == ["xcode-derived-data"])
    }

    // La catena reale: identità catturata dallo scanner, riverifica e cancellazione da parte di
    // CleanEngine con PathGuard, diario compreso.
    @Test func realCleanEngineDeletesTheRevalidatedFolderAndJournalsIt() async throws {
        let home = "/Users/test"
        let fs = InMemoryFileSystem()
        fs.addFile(Self.appPath + "/Build/Products/app", size: 64)
        let links = FakeLinkInspector()
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
        let scanner = XcodeFileScanner(
            fileSystem: fs, ruleScanner: RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: SystemWallClock()),
            pathGuard: pathGuard, links: links, sizeProbe: FakeSizeProbe(), homeDirectory: home)
        let collector = XcodeInventoryCollector(cli: FakeCli(), fileScanner: scanner)
        let plan = try confirm(try await collector.collect(), Self.appKey)
        let executor = XcodeCleanExecutor(
            cli: FakeCli(), collector: collector, cleanEngine: CleanEngine(fileSystem: fs, pathGuard: pathGuard, clock: SystemWallClock()),
            measures: FakeSizeProbe(), runningProbe: QueueRunningProbe(.notRunning), clock: SystemWallClock())
        let journal = JournalRecorder()

        let result = await executor.execute(plan, progress: nil, journal: journal)

        #expect(try single(result).outcome == .deleted)
        #expect(!fs.directoryExists(Self.appPath))
        #expect(fs.directoryExists(Self.derivedDataRoot))
        #expect(journal.paths.values == [Self.appPath])
        #expect(result.historyReport.deletedPaths == [Self.appPath])
    }

    // MARK: - Solo Swift: rivalidazione delle cartelle, diario, UUID dei runtime

    // Un'identità o un percorso cambiati fra conferma ed eliminazione fermano la cartella prima del
    // motore di pulizia: il confronto legge sempre l'inventario fresco, non il piano.
    @Test func changedFolderIdentityIsSkippedWithoutCallingCleanEngine() async throws {
        let plan = try confirm(fileSnapshot(allocatedBytes: 10, logicalBytes: 50), Self.appKey)
        let clean = FakeCleanEngine(itemsDeleted: 1)

        let result = await create(FakeCli(), QueueCollector(fileSnapshot(allocatedBytes: 10, logicalBytes: 60)), clean)
            .execute(plan, progress: nil, journal: nil)

        #expect(clean.calls.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
    }

    @Test func changedFolderPathIsSkippedWithoutCallingCleanEngine() async throws {
        let plan = try confirm(fileSnapshot(allocatedBytes: 10, logicalBytes: 50), Self.appKey)
        let clean = FakeCleanEngine(itemsDeleted: 1)
        let moved = folderSnapshot(candidatePath: Self.appPath + "-moved", allocatedBytes: 10, logicalBytes: 50)

        let result = await create(FakeCli(), QueueCollector(moved), clean).execute(plan, progress: nil, journal: nil)

        #expect(clean.calls.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
    }

    // NFC e NFD dello stesso nome sono due percorsi diversi per Xcode e per la riverifica, che
    // confronta i byte UTF-8 e non l'equivalenza canonica di String.
    @Test func canonicallyEquivalentFolderIdentityIsSkippedWithoutCallingCleanEngine() async throws {
        let composed = Self.derivedDataRoot + "/Caf\u{E9}-abc"
        let decomposed = Self.derivedDataRoot + "/Cafe\u{301}-abc"
        let plan = try confirm(folderSnapshot(path: composed, allocatedBytes: 10, logicalBytes: 50), "derived-data:" + composed)
        let clean = FakeCleanEngine(itemsDeleted: 1)
        let fresh = folderSnapshot(path: composed, identityPath: decomposed, allocatedBytes: 10, logicalBytes: 50)

        let result = await create(FakeCli(), QueueCollector(fresh), clean).execute(plan, progress: nil, journal: nil)

        #expect(clean.calls.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
    }

    @Test func unknownXcodeStateBlocksFilesWithoutCallingCleanEngine() async throws {
        let source = fileSnapshot(allocatedBytes: 10, logicalBytes: 50)
        let plan = try confirm(source, Self.appKey)
        let clean = FakeCleanEngine(itemsDeleted: 1)
        let executor = XcodeCleanExecutor(cli: FakeCli(), collector: QueueCollector(source), cleanEngine: clean, measures: FakeSizeProbe(),
                                          runningProbe: QueueRunningProbe(.unknown), clock: SystemWallClock())

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(clean.calls.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
    }

    // Il diario riceve un simulatore solo quando la verifica successiva lo trova assente: né un
    // comando riuscito con risorsa ancora presente, né un comando interrotto vi entrano.
    @Test func stillPresentAfterSuccessfulCommandIsNotJournaled() async throws {
        let plan = try confirm(snapshot(device()), Self.deviceId)
        let journal = JournalRecorder()

        let result = await create(FakeCli(), QueueCollector(snapshot(device()))).execute(plan, progress: nil, journal: journal)

        #expect(try single(result).outcome == .failed)
        #expect(journal.paths.values.isEmpty)
    }

    @Test func interruptedCommandIsNotJournaledEvenWhenTheDeviceIsAbsent() async throws {
        let plan = try confirm(snapshot(device()), Self.deviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: true)
        let journal = JournalRecorder()

        let result = await create(cli, QueueCollector(snapshot(device()), snapshot())).execute(plan, progress: nil, journal: journal)

        #expect(try single(result).outcome == .uncertain)
        #expect(journal.paths.values.isEmpty)
    }

    // Il runtime va rimosso per UUID canonico, mai per chiave («runtime:» più l'UUID).
    @Test func runtimeIsDeletedByItsCanonicalUuid() async throws {
        let plan = try confirm(snapshot(runtime([])), "runtime:" + Self.runtimeId)
        let cli = FakeCli()

        let result = await create(cli, QueueCollector(snapshot(runtime([])), snapshot())).execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedRuntimes.values == [Self.runtimeId])
        #expect(try single(result).outcome == .deleted)
    }

    // Se il motore non elimina la cartella, né lo storico né la stima la contano come rimossa.
    @Test func folderNotRemovedByCleanEngineIsSkippedWithoutCredit() async throws {
        let source = fileSnapshot(allocatedBytes: 10, logicalBytes: 50)
        let plan = try confirm(source, Self.appKey)

        let result = await create(FakeCli(), QueueCollector(source), FakeCleanEngine(itemsDeleted: 0))
            .execute(plan, progress: nil, journal: nil)

        #expect(try single(result).outcome == .skipped)
        #expect(result.historyReport.bytesFreed == 0)
        #expect(result.historyReport.deletedPaths.isEmpty)
    }
}
