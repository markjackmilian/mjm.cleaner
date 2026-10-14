/// `IXcodeCleanupService`: il punto d'ingresso della pagina Xcode.
public protocol XcodeCleanupServing: Sendable {
    func analyze() async throws -> XcodeSnapshot
    func execute(
        _ plan: XcodeConfirmedPlan,
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> XcodeCleanResult
}

/// Unisce l'inventario corrente a una verifica dello stato di Xcode che, nel dubbio, blocca.
public struct XcodeCleanupService: XcodeCleanupServing {
    private let collector: any XcodeInventoryCollecting
    private let runningProbe: any XcodeRunningProbing
    private let executor: any XcodeCleanExecuting

    public init(collector: any XcodeInventoryCollecting, runningProbe: any XcodeRunningProbing, executor: any XcodeCleanExecuting) {
        self.collector = collector
        self.runningProbe = runningProbe
        self.executor = executor
    }

    public func analyze() async throws -> XcodeSnapshot {
        let snapshot = try await collector.collect()
        let state = try await runningProbe.state()
        if state == .unknown {
            let blocked = snapshot.candidates.map { candidate in
                guard candidate.kind == .derivedData || candidate.kind == .deviceSupport else { return candidate }
                var copy = candidate
                copy.blockReason = candidate.blockReason
                    ?? String(localized: "Impossibile verificare se Xcode è in esecuzione; ripeti l'analisi.", bundle: .module)
                return copy
            }
            return XcodeSnapshot(candidates: blocked, warnings: snapshot.warnings, fileInventory: snapshot.fileInventory)
        }

        return try XcodeClassifier.classify(snapshot, xcodeRunning: state == .running)
    }

    /// Il chiamante scarta il diario solo dopo aver scritto il log di sessione (spec §8.2).
    public func execute(
        _ plan: XcodeConfirmedPlan,
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> XcodeCleanResult {
        await executor.execute(plan, progress: progress, journal: journal)
    }
}
