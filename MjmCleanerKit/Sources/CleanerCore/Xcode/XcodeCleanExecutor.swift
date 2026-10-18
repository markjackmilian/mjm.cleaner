import Foundation

/// `IXcodeCleanExecutor`.
public protocol XcodeCleanExecuting: Sendable {
    func execute(
        _ plan: XcodeConfirmedPlan,
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> XcodeCleanResult
}

/// Esegue solo le risorse confermate, riverificando ciascuna subito prima della rimozione. Non
/// lancia mai: l'annullamento e gli errori diventano esiti dei singoli elementi.
///
/// Diario (spec §8.2, assente nel C#): le cartelle passano da `CleanEngine`, che registra ogni
/// percorso eliminato nel `journal`; simulatori e runtime rimossi con verifica vi si registrano
/// con lo stesso testo che finisce fra i percorsi eliminati dello storico.
public struct XcodeCleanExecutor: XcodeCleanExecuting {
    private static let verificationTimeout: Duration = .seconds(15)

    private let cli: any XcodeCliInvoking
    private let collector: any XcodeInventoryCollecting
    private let cleanEngine: any CleanPerforming
    private let measures: any XcodeSizeProbing
    private let runningProbe: any XcodeRunningProbing
    private let clock: any WallClock

    public init(
        cli: any XcodeCliInvoking,
        collector: any XcodeInventoryCollecting,
        cleanEngine: any CleanPerforming,
        measures: any XcodeSizeProbing,
        runningProbe: any XcodeRunningProbing,
        clock: any WallClock
    ) {
        self.cli = cli
        self.collector = collector
        self.cleanEngine = cleanEngine
        self.measures = measures
        self.runningProbe = runningProbe
        self.clock = clock
    }

    @concurrent
    public func execute(
        _ plan: XcodeConfirmedPlan,
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> XcodeCleanResult {
        let started = clock.now
        let start = ContinuousClock.now
        var results: [XcodeItemResult] = []
        var warnings: [String] = []
        let freeBefore = await tryFreeBytes()
        let ordered = plan.candidates.filter { $0.kind == .device }
            + plan.candidates.filter { $0.kind == .runtime }
            + plan.candidates.filter { Self.isFile($0.kind) }
        var deletedDevices = Set<[UInt8]>()

        for approved in ordered {
            if Task.isCancelled {
                results.append(Self.result(approved, .skipped, String(localized: "Operazione annullata prima della rimozione.", bundle: .module), nil))
                continue
            }

            do {
                let running = try await runningProbe.state()
                let fresh = try await collector.collect()
                warnings.append(contentsOf: XcodeText.distinct(fresh.warnings.map(\.message)))
                guard Self.isInventoryReadable(fresh, approved.kind) else {
                    results.append(Self.result(approved, .skipped, String(localized: "Inventario non disponibile per verificare la risorsa.", bundle: .module), nil))
                    continue
                }

                let classified = try XcodeClassifier.classify(fresh, xcodeRunning: running == .running)
                if running == .unknown && Self.isFile(approved.kind) {
                    results.append(Self.result(approved, .skipped, String(localized: "Impossibile verificare se Xcode è in esecuzione.", bundle: .module), nil))
                    continue
                }

                guard let current = classified.candidates.first(where: { Self.sameKey($0.key, approved.key) }) else {
                    results.append(Self.result(approved, .skipped, String(localized: "La risorsa approvata non è più presente nell'inventario.", bundle: .module), nil))
                    continue
                }

                if let changed = Self.compareIdentity(plan, fresh, approved, current, deletedDevices) {
                    results.append(Self.result(approved, .skipped, changed, nil))
                    continue
                }

                if let blockReason = current.blockReason {
                    results.append(Self.result(approved, .skipped, blockReason, nil))
                    continue
                }

                if approved.kind == .runtime {
                    let dependentSelected = approved.dependentDeviceKeys.filter { key in
                        plan.candidates.contains { $0.kind == .device && Self.sameKey($0.key, key) }
                    }
                    if dependentSelected.contains(where: { !deletedDevices.contains(XcodeText.caseInsensitiveKey($0)) }) {
                        results.append(Self.result(approved, .skipped, String(localized: "Un dispositivo dipendente selezionato non è stato rimosso con verifica.", bundle: .module), nil))
                        continue
                    }
                }

                if Self.isFile(approved.kind) {
                    await executeFile(plan, approved, freshAllocatedBytes: current.sizeBytes, progress, journal, &results, &warnings)
                    continue
                }

                await executeCli(approved, progress, journal, &results, &warnings)
                if approved.kind == .device, results.last?.outcome == .deleted {
                    deletedDevices.insert(XcodeText.caseInsensitiveKey(XcodeClassifier.normalizeSelectionKey(approved.key)))
                }
            } catch is CancellationError where Task.isCancelled {
                results.append(Self.result(approved, .skipped, String(localized: "Operazione annullata prima della rimozione.", bundle: .module), nil))
            } catch {
                results.append(Self.result(approved, .failed, XcodeText.message(error), nil))
            }

            progress?(CleanProgress(currentPath: approved.path ?? approved.name, itemsDone: results.count, itemsTotal: ordered.count, bytesFreed: 0))
        }

        // Come CancellationToken.None in C#: lo spazio finale si legge anche dopo un annullamento.
        let freeAfter = await Task { await tryFreeBytes() }.value
        let report = Self.makeHistory(started, ContinuousClock.now - start, results)
        return XcodeCleanResult(
            historyReport: report,
            items: results,
            freeBytesBefore: freeBefore,
            freeBytesAfter: freeAfter,
            warnings: XcodeText.distinct(warnings))
    }

    private func executeFile(
        _ plan: XcodeConfirmedPlan,
        _ candidate: XcodeCandidate,
        freshAllocatedBytes: Int64?,
        _ progress: (@Sendable (CleanProgress) -> Void)?,
        _ journal: (any DeletionRecording)?,
        _ results: inout [XcodeItemResult],
        _ warnings: inout [String]
    ) async {
        guard let approvedEntry = plan.fileInventory[candidate.key], approvedEntry.identity.logicalSizeBytes != nil else {
            results.append(Self.result(candidate, .skipped, String(localized: "Identità della cartella incompleta.", bundle: .module), nil))
            return
        }

        let report = await cleanEngine.clean(
            [CategorySelection(categoryId: Self.category(candidate.kind), items: [approvedEntry.item])],
            progress: progress,
            journal: journal)
        if report.itemsDeleted == 1 {
            results.append(Self.result(candidate, .deleted, String(localized: "Cartella rimossa e verificata dal motore di pulizia.", bundle: .module), freshAllocatedBytes))
        } else if let error = report.errors.first {
            results.append(Self.result(candidate, .failed, error.message, nil))
        } else {
            results.append(Self.result(candidate, .skipped, String(localized: "La cartella non è stata rimossa.", bundle: .module), nil))
        }

        if report.itemsFailed > 0 {
            warnings.append(contentsOf: report.errors.map(\.message))
        }
    }

    private func executeCli(
        _ candidate: XcodeCandidate,
        _ progress: (@Sendable (CleanProgress) -> Void)?,
        _ journal: (any DeletionRecording)?,
        _ results: inout [XcodeItemResult],
        _ warnings: inout [String]
    ) async {
        var command: ProcessResult?
        var commandError: (any Error)?
        do {
            // Il classificatore ha già verificato l'UUID; un identificativo mancante arriva vuoto e
            // viene respinto dalla CLI come in C#, senza avviare alcun processo.
            let uuid = candidate.cliId ?? ""
            command = candidate.kind == .device ? try await cli.deleteDevice(uuid) : try await cli.deleteRuntime(uuid)
        } catch {
            commandError = error
        }

        let verified = await tryVerifyAfterCommand(&warnings)
        if let verified {
            warnings.append(contentsOf: XcodeText.distinct(verified.warnings.map(\.message)))
        }

        let failedFallback = String(localized: "Il comando di rimozione non è riuscito.", bundle: .module)
        if let verified, Self.isInventoryReadable(verified, candidate.kind) {
            if commandError is CancellationError || command?.timedOut == true || Task.isCancelled {
                results.append(Self.result(candidate, .uncertain, String(localized: "Il comando è stato interrotto; l'assenza successiva non viene attribuita a questa pulizia.", bundle: .module), nil))
            } else if commandError != nil || command == nil || command?.exitCode != 0 {
                let reason = commandError.map(XcodeText.message) ?? command.map { XcodeText.trimmed($0.standardError) } ?? ""
                results.append(Self.result(candidate, .failed, XcodeText.isNullOrWhiteSpace(reason) ? failedFallback : reason, nil))
            } else if !verified.candidates.contains(where: { Self.sameKey($0.key, candidate.key) }) {
                let estimate = candidate.sizeBytes
                let reason = estimate == nil
                    ? String(localized: "Risorsa assente dopo il comando; dimensione stimata sconosciuta.", bundle: .module)
                    : String(localized: "Risorsa assente dopo il comando.", bundle: .module)
                results.append(Self.result(candidate, .deleted, reason, estimate))
                journal?.recordDeleted(candidate.path ?? candidate.key)
            } else {
                // Qui il comando è riuscito (uscita 0, nessun errore): la risorsa è ancora presente.
                let reason = String(localized: "Il comando è riuscito ma la risorsa è ancora presente.", bundle: .module)
                results.append(Self.result(candidate, .failed, reason, nil))
            }
        } else {
            results.append(Self.result(candidate, .uncertain, String(localized: "Il comando è terminato senza poter verificare l'inventario successivo.", bundle: .module), nil))
        }

        progress?(CleanProgress(currentPath: candidate.name, itemsDone: results.count, itemsTotal: results.count, bytesFreed: 0))
    }

    /// Inventario di verifica con un proprio limite di 15 secondi e indipendente dall'annullamento
    /// del chiamante, come il `CancellationTokenSource` dedicato del C#: un comando già lanciato va
    /// sempre verificato. Un task non strutturato non eredita l'annullamento.
    private func tryVerifyAfterCommand(_ warnings: inout [String]) async -> XcodeSnapshot? {
        let collector = self.collector
        let bounded = Task { () async throws -> XcodeSnapshot in
            try await withThrowingTaskGroup(of: XcodeSnapshot?.self) { group in
                group.addTask { try await collector.collect() }
                group.addTask {
                    try await Task.sleep(for: Self.verificationTimeout)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let snapshot = first else { throw CancellationError() }
                return snapshot
            }
        }

        do {
            return try await bounded.value
        } catch {
            warnings.append(String(localized: "Verifica successiva non disponibile: \(XcodeText.message(error))", bundle: .module))
            return nil
        }
    }

    private func tryFreeBytes() async -> Int64? {
        do {
            return try await measures.freeBytes()
        } catch {
            return nil
        }
    }

    private static func isInventoryReadable(_ snapshot: XcodeSnapshot, _ kind: XcodeResourceKind) -> Bool {
        !snapshot.warnings.contains { $0.resourceGroup == kind && $0.kind == .completenessFailure }
    }

    /// Il motivo per cui la risorsa non è più quella approvata, oppure `nil`.
    private static func compareIdentity(
        _ plan: XcodeConfirmedPlan,
        _ fresh: XcodeSnapshot,
        _ approved: XcodeCandidate,
        _ current: XcodeCandidate,
        _ deletedDevices: Set<[UInt8]>
    ) -> String? {
        if current.kind != approved.kind {
            return String(localized: "Il tipo della risorsa è cambiato dall'analisi.", bundle: .module)
        }

        if isFile(approved.kind) {
            guard let approvedPath = approved.path, let currentPath = current.path, XcodeText.same(approvedPath, currentPath),
                  let captured = plan.fileInventory[approved.key],
                  let observed = fresh.fileInventory[approved.key],
                  sameFileIdentity(captured, observed) else {
                return String(localized: "Il percorso o i metadati della cartella sono cambiati dall'analisi.", bundle: .module)
            }
            return nil
        }

        guard let oldId = approved.cliId.flatMap(XcodeUuid.canonical),
              let newId = current.cliId.flatMap(XcodeUuid.canonical), oldId == newId,
              XcodeText.same(approved.build, current.build),
              approved.kind != .runtime || XcodeText.same(approved.runtimeIdentifier, current.runtimeIdentifier) else {
            return String(localized: "L'identità o la build della risorsa è cambiata dall'analisi.", bundle: .module)
        }

        if approved.kind == .runtime {
            let expected = approved.dependentDeviceKeys.map(XcodeClassifier.normalizeSelectionKey)
                .filter { !deletedDevices.contains(XcodeText.caseInsensitiveKey($0)) }
                .map(XcodeText.ordinalKey)
                .sorted { $0.lexicographicallyPrecedes($1) }
            let actual = current.dependentDeviceKeys.map(XcodeClassifier.normalizeSelectionKey)
                .map(XcodeText.ordinalKey)
                .sorted { $0.lexicographicallyPrecedes($1) }
            if expected != actual {
                return String(localized: "Le dipendenze del runtime sono cambiate dall'analisi.", bundle: .module)
            }
        }

        return nil
    }

    private static func sameFileIdentity(_ captured: XcodeFileEntry, _ observed: XcodeFileEntry) -> Bool {
        captured.identity.logicalSizeBytes != nil
            && observed.identity.logicalSizeBytes != nil
            && XcodeText.same(captured.identity.canonicalPath, observed.identity.canonicalPath)
            && captured.identity.isDirectory == observed.identity.isDirectory
            && captured.identity.creationTime == observed.identity.creationTime
            && captured.identity.lastWriteTime == observed.identity.lastWriteTime
            && captured.identity.logicalSizeBytes == observed.identity.logicalSizeBytes
            && captured.item.isDirectory == observed.item.isDirectory
            && XcodeText.same(captured.item.path, observed.item.path)
            && XcodeText.same(captured.item.declaredRoot, observed.item.declaredRoot)
    }

    private static func sameKey(_ left: String, _ right: String) -> Bool {
        XcodeText.same(XcodeClassifier.normalizeSelectionKey(left), XcodeClassifier.normalizeSelectionKey(right))
    }

    private static func isFile(_ kind: XcodeResourceKind) -> Bool {
        kind == .derivedData || kind == .deviceSupport
    }

    private static func category(_ kind: XcodeResourceKind) -> String {
        switch kind {
        case .derivedData: "xcode-derived-data"
        case .deviceSupport: "xcode-device-support"
        case .device: "xcode-simulator-devices"
        case .runtime: "xcode-runtimes"
        }
    }

    private static func result(_ candidate: XcodeCandidate, _ outcome: XcodeItemOutcome, _ reason: String, _ bytes: Int64?) -> XcodeItemResult {
        XcodeItemResult(candidate: candidate, outcome: outcome, reason: reason, verifiedEstimatedBytes: bytes)
    }

    /// Lo storico conta solo le rimozioni verificate e, per ciascuna, la stima allocata fresca.
    private static func makeHistory(_ started: Date, _ duration: Duration, _ results: [XcodeItemResult]) -> CleanReport {
        let deleted = results.filter { $0.outcome == .deleted }
        let bytes = deleted.reduce(Int64(0)) { $0 + ($1.verifiedEstimatedBytes ?? 0) }

        var categories: [CategoryCleanResult] = []
        for result in deleted {
            let id = category(result.candidate.kind)
            let freed = result.verifiedEstimatedBytes ?? 0
            if let index = categories.firstIndex(where: { $0.categoryId == id }) {
                let existing = categories[index]
                categories[index] = CategoryCleanResult(categoryId: id, bytesFreed: existing.bytesFreed + freed, itemsDeleted: existing.itemsDeleted + 1)
            } else {
                categories.append(CategoryCleanResult(categoryId: id, bytesFreed: freed, itemsDeleted: 1))
            }
        }

        let errors = results.filter { $0.outcome != .deleted }
            .map { ScanError(path: $0.candidate.path ?? $0.candidate.name, kind: .other, message: $0.reason) }
        return CleanReport(
            startedAt: started,
            duration: duration,
            bytesFreed: bytes,
            itemsDeleted: deleted.count,
            itemsFailed: errors.count,
            categories: categories,
            errors: errors,
            deletedPaths: deleted.map { $0.candidate.path ?? $0.candidate.key })
    }
}
