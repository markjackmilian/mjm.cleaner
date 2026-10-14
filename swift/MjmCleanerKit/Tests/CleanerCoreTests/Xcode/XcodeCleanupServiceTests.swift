import Testing
@testable import CleanerCore

struct XcodeCleanupServiceTests {
    private struct ProcessListingRunner: ProcessRunning {
        let outcome: Result<ProcessResult, any Error>

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            try outcome.get()
        }
    }

    @Test(arguments: [
        ("/Applications/Xcode.app/Contents/MacOS/Xcode", XcodeRunningState.running),
        ("/Applications/Xcode-beta.app/Contents/MacOS/Xcode-beta", .running),
        ("/usr/bin/simctl", .notRunning),
    ])
    func runningProbeClassifiesProcessListing(processPath: String, expected: XcodeRunningState) async throws {
        let probe = XcodeRunningProbe(runner: ProcessListingRunner(
            outcome: .success(ProcessResult(exitCode: 0, standardOutput: processPath, standardError: "", timedOut: false))))

        #expect(try await probe.state() == expected)
    }

    @Test func runningProbeReturnsUnknownWhenListingFails() async throws {
        let probe = XcodeRunningProbe(runner: ProcessListingRunner(
            outcome: .success(ProcessResult(exitCode: 1, standardOutput: "", standardError: "denied", timedOut: false))))

        #expect(try await probe.state() == .unknown)
    }

    // Solo Swift: timeout, avvio fallito e stderr non vuoto non vengono mai scambiati per
    // «Xcode chiuso», anche quando lo stdout elenca processi qualunque.
    @Test(arguments: [
        Result<ProcessResult, any Error>.success(ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true)),
        .success(ProcessResult(exitCode: 0, standardOutput: "/usr/bin/simctl", standardError: "ps: warning", timedOut: false)),
        .failure(ProcessLaunchError(executable: "ps", code: 2)),
    ])
    func runningProbeIsUnknownWhenTheListingIsNotReliable(outcome: Result<ProcessResult, any Error>) async throws {
        let probe = XcodeRunningProbe(runner: ProcessListingRunner(outcome: outcome))

        #expect(try await probe.state() == .unknown)
    }
}

extension XcodeCleanupServiceTests {
    private struct FixedCollector: XcodeInventoryCollecting {
        let snapshot: XcodeSnapshot

        func collect() async throws -> XcodeSnapshot { snapshot }
    }

    private struct FixedRunningProbe: XcodeRunningProbing {
        let value: XcodeRunningState

        func state() async throws -> XcodeRunningState { value }
    }

    /// Porting di `RecordingExecutor`, che in C# lanciava sempre: qui registra la chiamata, così
    /// il test solo Swift verifica anche l'inoltro del diario.
    private struct RecordingExecutor: XcodeCleanExecuting {
        let journals = Recorder<Bool>()

        func execute(_ plan: XcodeConfirmedPlan, progress: (@Sendable (CleanProgress) -> Void)?, journal: (any DeletionRecording)?) async -> XcodeCleanResult {
            journals.append(journal != nil)
            let report = CleanReport(startedAt: .distantPast, duration: .zero, bytesFreed: 0, itemsDeleted: 0, itemsFailed: 0,
                                     categories: [], errors: [], deletedPaths: [])
            return XcodeCleanResult(historyReport: report, items: [], freeBytesBefore: nil, freeBytesAfter: nil, warnings: [])
        }
    }

    private struct NoJournal: DeletionRecording {
        func recordDeleted(_ path: String) {}
    }

    @Test func analyzeBlocksFilesWhenXcodeStateCannotBeVerified() async throws {
        let path = "/Users/test/Library/Developer/Xcode/DerivedData/App"
        let raw = XcodeSnapshot(candidates: [XcodeCandidate(key: "derived-data:" + path, kind: .derivedData, name: "App", path: path)], warnings: [])
        let service = XcodeCleanupService(collector: FixedCollector(snapshot: raw), runningProbe: FixedRunningProbe(value: .unknown), executor: RecordingExecutor())

        let analyzed = try await service.analyze()

        #expect(analyzed.candidates.count == 1)
        #expect(analyzed.candidates.first?.blockReason != nil)
    }

    // Solo Swift: l'esecuzione passa all'esecutore piano, avanzamento e diario.
    @Test func executeForwardsThePlanAndTheJournalToTheExecutor() async throws {
        let device = XcodeCandidate(key: "11111111-1111-4111-8111-111111111111", kind: .device, name: "iPhone",
                                    cliId: "11111111-1111-4111-8111-111111111111", state: "Shutdown")
        let plan = try XcodeSelection.confirm(
            XcodeSelection.preview(XcodeSnapshot(candidates: [device], warnings: []), selectedKeys: [device.key]), acknowledgeDependencies: true)
        let executor = RecordingExecutor()
        let service = XcodeCleanupService(collector: FixedCollector(snapshot: .empty), runningProbe: FixedRunningProbe(value: .notRunning), executor: executor)

        _ = await service.execute(plan, progress: nil, journal: NoJournal())

        #expect(executor.journals.values == [true])
    }
}
