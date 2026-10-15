import CleanerCore
import Foundation
import Synchronization
import Testing
@testable import CleanerFeatures

@MainActor
struct XcodeViewModelTests {
    @Test func groupSelectionOnlyAffectsCaches() async throws {
        let service = FakeXcode(Self.snapshot(
            Self.candidate("dd", .derivedData), Self.candidate("support", .deviceSupport),
            Self.candidate("device", .device), Self.candidate("runtime", .runtime)))
        let model = Self.create(service)
        await model.initialLoad?.value
        #expect(model.groups.flatMap(\.rows).allSatisfy { !$0.isSelected })

        let cache = try Self.group(model, .derivedData)
        cache.isSelected = true
        #expect(cache.rows.allSatisfy { $0.isSelected })
        let support = try Self.group(model, .deviceSupport)
        support.isSelected = true
        #expect(support.rows.allSatisfy { $0.isSelected })

        let individual = model.groups.filter { $0.kind == .device || $0.kind == .runtime }
        #expect(individual.flatMap(\.rows).allSatisfy { !$0.isSelected })
        #expect(individual.allSatisfy { !$0.showGroupCheckBox })
    }

    @Test func deleteRequiresPreviewAndAcknowledgement() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("runtime", .runtime, dependencies: ["device"]), Self.candidate("device", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        try Self.onlyRow(model, .runtime).isSelected = true
        #expect(!model.canConfirmDelete)

        model.preview()
        #expect(model.confirmation?.retainedDependentDevices.count == 1)
        #expect(!model.canConfirmDelete)

        model.acknowledgeDependencies = true
        #expect(model.canConfirmDelete)
    }

    @Test func doubleClickExecutesOnce() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("device", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true
        model.preview()

        let first = Task { await model.confirmDelete() }
        try await service.executionStarted.wait()
        let second = Task { await model.confirmDelete() }
        await second.value
        #expect(service.executeCount == 1)

        service.execution.open(Self.result())
        await first.value

        #expect(service.executeCount == 1)
        #expect(!model.canConfirmDelete)
    }

    @Test func retryClearsOldSelection() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("one", .device)), Self.snapshot(Self.candidate("two", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true

        await model.retry()

        let row = try Self.onlyRow(model, .device)
        #expect(row.candidate.name == "two")
        #expect(!row.isSelected)
    }

    @Test func unknownOnlyGroupSummaryDoesNotDisplayZeroBytes() {
        var unknown = Self.candidate("unknown", .deviceSupport)
        unknown.sizeBytes = nil
        let group = XcodeGroupNode(kind: .deviceSupport, candidates: [unknown], warnings: [])

        #expect(group.summary.contains("dimensioni non disponibili"))
        #expect(!group.summary.contains("0 B"))
    }

    @Test func emptyGroupSummaryShowsZeroEntriesWithoutSizeWarning() {
        let group = XcodeGroupNode(kind: .deviceSupport, candidates: [], warnings: [])

        #expect(group.summary.contains("0 voci"))
        #expect(!group.summary.contains("dimensioni non disponibili"))
    }

    @Test func mixedGroupSummaryLabelsKnownEstimateAndUnknownCount() {
        var known = Self.candidate("known", .derivedData)
        known.sizeBytes = 2048
        var unknown = Self.candidate("unknown", .derivedData)
        unknown.sizeBytes = nil
        let group = XcodeGroupNode(kind: .derivedData, candidates: [known, unknown], warnings: [])

        #expect(group.summary.contains("noti"))
        #expect(group.summary.contains("1 dimensione non disponibile"))
    }

    @Test func cannotNavigateDuringDelete() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("device", .device)))
        let navigation = FakeNavigation()
        let model = Self.create(service, navigation)
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true
        model.preview()

        let deleting = Task { await model.confirmDelete() }
        try await service.executionStarted.wait()
        model.close()
        model.backToSelection()

        #expect(navigation.navigationCount == 0)
        #expect(!model.canNavigate)
        service.execution.open(Self.result())
        await deleting.value
    }

    @Test func cancelDeleteReturnsAndPersistsPartialReportOnce() async throws {
        let history = FakeHistory()
        let log = FakeSessionLog()
        let partial = XcodeCleanResult(
            historyReport: makeReport(),
            items: [XcodeItemResult(candidate: Self.candidate("device", .device), outcome: .skipped, reason: "annullata", verifiedEstimatedBytes: nil)],
            freeBytesBefore: 10, freeBytesAfter: 10, warnings: [])
        let service = FakeXcode(Self.snapshot(Self.candidate("device", .device)))
        service.returnWhenCancelled(partial)
        let model = XcodeModel(xcode: service, history: history, sessionLog: log, clock: Self.clock, navigation: FakeNavigation())
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true
        model.preview()

        let deleting = Task { await model.confirmDelete() }
        try await service.executionStarted.wait()
        model.cancelDelete()
        await deleting.value
        #expect(service.observedCancellation == [true])
        let report = try #require(model.currentReport)
        await report.persistence?.value
        await report.persist()

        #expect(report.items.count == 1)
        #expect(report.items.first?.outcomeText == "Saltata")
        #expect(history.saves == 1)
        #expect(log.writes == 1)
    }

    /// In C# il primo tentativo falliva perché l'esecutore lanciava un'eccezione. In Swift
    /// l'esecutore non lancia mai: l'unico fallimento possibile è la conferma, che rifiuta un piano
    /// con dispositivi dipendenti non presi in carico. Il comportamento verificato è lo stesso:
    /// dopo un fallimento si può riprovare e confermare di nuovo.
    @Test func retryAfterExecutionFailureCanConfirmAgain() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("runtime", .runtime, dependencies: ["device"]), Self.candidate("device", .device)))
        service.respondImmediately(with: Self.result())
        let navigation = FakeNavigation()
        let model = Self.create(service, navigation)
        await model.initialLoad?.value
        try Self.onlyRow(model, .runtime).isSelected = true
        model.preview()

        await model.confirmDelete()
        #expect(model.errorText.hasPrefix("Pulizia Xcode non riuscita: "))
        #expect(service.executeCount == 0)

        await model.retry()
        try Self.onlyRow(model, .runtime).isSelected = true
        model.preview()
        model.acknowledgeDependencies = true
        #expect(model.canConfirmDelete)
        await model.confirmDelete()

        #expect(service.executeCount == 1)
        #expect(navigation.navigationCount == 1)
        #expect(model.currentReport != nil)
    }

    // Solo Swift: diario della pulizia (spec §8.2), avvisi, totali, anteprima scartata, errori.

    @Test func journalIsOpenedBeforeExecutionAndDiscardedByTheReport() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let log = FakeSessionLog(events: events, journalDirectory: directory.path)
        let service = FakeXcode(Self.snapshot(Self.candidate("device", .device)))
        service.respondImmediately(with: Self.result())
        let model = XcodeModel(xcode: service, history: FakeHistory(events: events), sessionLog: log, clock: Self.clock, navigation: FakeNavigation())
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true
        model.preview()

        await model.confirmDelete()
        await model.currentReport?.persistence?.value

        #expect(service.receivedJournal == [true])
        #expect(events.values == ["open", "save", "write", "discard"])
        #expect(log.discarded.count == 1)
    }

    @Test func warningsAreShownOnceAndPerGroup() async throws {
        let snapshot = XcodeSnapshot(
            candidates: [Self.candidate("device", .device)],
            warnings: [
                .completenessFailure(.device, "Inventario dei simulatori incompleto."),
                .advisory(.runtime, "Rimozione dei runtime non supportata."),
                .completenessFailure(.device, "Inventario dei simulatori incompleto."),
            ])
        let model = Self.create(FakeXcode(snapshot))
        await model.initialLoad?.value

        #expect(model.warningText == "Inventario dei simulatori incompleto.\nRimozione dei runtime non supportata.")
        #expect(model.hasWarnings)
        #expect(try Self.group(model, .device).warnings == ["Inventario dei simulatori incompleto.", "Inventario dei simulatori incompleto."])
        #expect(try Self.group(model, .runtime).warnings == ["Rimozione dei runtime non supportata."])
    }

    @Test func totalCountsKnownAndUnknownSizesWithoutOverflow() async throws {
        var huge = Self.candidate("huge", .derivedData)
        huge.sizeBytes = Int64.max
        var unknown = Self.candidate("unknown", .derivedData)
        unknown.sizeBytes = nil
        let model = Self.create(FakeXcode(Self.snapshot(huge, Self.candidate("small", .derivedData), unknown)))
        await model.initialLoad?.value
        #expect(model.totalText == "0 B stimati · 0 selezionate")

        try Self.group(model, .derivedData).isSelected = true

        #expect(model.totalText == "8388608 TB stimati · 3 selezionate · 1 non disponibili")
        #expect(try Self.group(model, .derivedData).summary == "3 voci · 8388608 TB stimati noti · 1 dimensione non disponibile")
    }

    @Test func changingTheSelectionDiscardsThePreview() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("runtime", .runtime, dependencies: ["device"]), Self.candidate("device", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        try Self.onlyRow(model, .runtime).isSelected = true
        model.preview()
        model.acknowledgeDependencies = true
        #expect(model.hasConfirmation)
        #expect(model.hasRetainedDependencies)
        #expect(model.hasSelectedRuntimes)
        #expect(!model.hasSelectedDevices)

        try Self.onlyRow(model, .device).isSelected = true

        #expect(!model.hasConfirmation)
        #expect(!model.acknowledgeDependencies)
        #expect(model.previewSummaryText == "")
    }

    @Test func analysisFailureIsShown() async throws {
        let service = FakeXcode()
        service.failAnalysis(with: XcodeUnavailableError("Xcode command line tools non trovati."))
        let model = Self.create(service)
        await model.initialLoad?.value

        #expect(model.errorText == "Analisi Xcode non riuscita: Xcode command line tools non trovati.")
        #expect(model.groups.isEmpty)
        #expect(model.canRetry)
    }

    // Solo Swift (review del Task 10): ciò che la pagina consegna all'esecutore e le guardie.

    /// All'esecutore arrivano esattamente le risorse dell'anteprima: né quelle non selezionate né i
    /// simulatori dipendenti che l'utente ha scelto di tenere.
    @Test func executeReceivesExactlyThePreviewedResources() async throws {
        let runtime = Self.candidate("runtime", .runtime, dependencies: ["device"])
        let service = FakeXcode(Self.snapshot(runtime, Self.candidate("device", .device), Self.candidate("other", .device)))
        service.respondImmediately(with: Self.result())
        let model = Self.create(service)
        await model.initialLoad?.value
        try Self.onlyRow(model, .runtime).isSelected = true
        model.preview()
        model.acknowledgeDependencies = true

        await model.confirmDelete()

        #expect(service.executedKeys == [[runtime.key]])
    }

    /// Le righe bloccate non entrano mai nella selezione, nemmeno dalla casella del gruppo; i gruppi di
    /// simulatori e runtime non hanno una casella che selezioni.
    @Test func blockedRowsAndIndividualGroupsAreNeverSelectedTogether() async throws {
        var blocked = Self.candidate("blocked", .derivedData)
        blocked.blockReason = "Xcode è in esecuzione"
        let service = FakeXcode(Self.snapshot(blocked, Self.candidate("free", .derivedData), Self.candidate("device", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        let derivedData = try Self.group(model, .derivedData)
        let blockedRow = try #require(derivedData.rows.first { $0.candidate.name == "blocked" })

        derivedData.isSelected = true
        #expect(!blockedRow.isSelected)
        #expect(model.selectedKeys() == ["free"])
        #expect(model.totalText == "100 B stimati · 1 selezionate")

        blockedRow.isSelected = true
        #expect(model.selectedKeys() == ["free"])

        try Self.group(model, .device).isSelected = true
        #expect(try Self.onlyRow(model, .device).isSelected == false)
        #expect(model.selectedKeys() == ["free"])
    }

    /// Una nuova analisi non lascia una conferma della precedente; una analisi fallita svuota la pagina.
    @Test func retryDropsTheOldConfirmationAndAFailedRetryEmptiesThePage() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("device", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true
        model.preview()
        #expect(model.hasConfirmation)

        await model.retry()
        #expect(!model.hasConfirmation)
        #expect(!model.canConfirmDelete)

        service.failAnalysis(with: UnexpectedTestError(description: "simctl non risponde"))
        await model.retry()
        #expect(model.groups.isEmpty)
        model.preview()
        #expect(!model.hasConfirmation)
    }

    /// Durante l'eliminazione anteprima e «Torna alla selezione» non toccano la conferma in corso; una
    /// conferma vuota non abilita l'eliminazione.
    @Test func previewAndBackToSelectionAreIgnoredWhileDeleting() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("runtime", .runtime, dependencies: ["device"]), Self.candidate("device", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        model.preview()
        #expect(model.confirmation?.selectedCandidates.isEmpty == true)
        #expect(!model.canConfirmDelete)

        try Self.onlyRow(model, .runtime).isSelected = true
        model.preview()
        model.acknowledgeDependencies = true
        let deleting = Task { await model.confirmDelete() }
        try await service.executionStarted.wait()

        model.preview()
        model.backToSelection()
        #expect(model.hasConfirmation)
        #expect(model.acknowledgeDependencies)

        service.execution.open(Self.result())
        await deleting.value
    }

    @Test func progressIsAppliedBeforeShowingTheReport() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("uno", .device), Self.candidate("due", .device), Self.candidate("tre", .device)))
        service.respondImmediately(with: Self.result())
        let navigation = ProgressSnapshotNavigation()
        let model = XcodeModel(xcode: service, history: FakeHistory(), sessionLog: FakeSessionLog(), clock: Self.clock, navigation: navigation)
        navigation.model = model
        await model.initialLoad?.value
        for row in try Self.group(model, .device).rows { row.isSelected = true }
        model.preview()

        await model.confirmDelete()

        #expect(navigation.progressAtReport.count == 1)
        #expect(navigation.progressAtReport.first?.hasPrefix("3 / 3 · ") == true)
    }

    // MARK: Doppi e fixture (in C# classi interne di questa classe di test)

    static let clock = FixedWallClock(now: Date(timeIntervalSince1970: 1_790_000_000))

    static func snapshot(_ candidates: XcodeCandidate...) -> XcodeSnapshot {
        XcodeSnapshot(candidates: candidates, warnings: [])
    }

    /// Come il C#: un UUID deterministico ricavato dalla chiave (là con MD5, qui con FNV-1a: i
    /// valori cambiano, la proprietà no), chiave "runtime:<uuid>" per i runtime e l'UUID stesso per
    /// i simulatori.
    static func candidate(_ key: String, _ kind: XcodeResourceKind, dependencies: [String]? = nil) -> XcodeCandidate {
        let id = uuid(key)
        let identity = kind == .runtime ? "runtime:" + id : kind == .device ? id : key
        return XcodeCandidate(
            key: identity, kind: kind, name: key,
            cliId: kind == .device || kind == .runtime ? id : nil,
            state: kind == .device ? "Shutdown" : nil,
            sizeBytes: 100,
            dependencies: dependencies?.map(uuid))
    }

    static func uuid(_ key: String) -> String {
        var first: UInt64 = 0xcbf2_9ce4_8422_2325
        var second: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in key.utf8 {
            first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            second = (second ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 &+ 1
        }
        let hex = Array(String(format: "%016llx%016llx", first, second))
        return [hex[0..<8], hex[8..<12], hex[12..<16], hex[16..<20], hex[20..<32]].map { String($0) }.joined(separator: "-")
    }

    static func result() -> XcodeCleanResult {
        XcodeCleanResult(historyReport: makeReport(), items: [], freeBytesBefore: 100, freeBytesAfter: 120, warnings: [])
    }

    static func create(_ service: FakeXcode, _ navigation: FakeNavigation = FakeNavigation()) -> XcodeModel {
        XcodeModel(xcode: service, history: FakeHistory(), sessionLog: FakeSessionLog(), clock: clock, navigation: navigation)
    }

    static func group(_ model: XcodeModel, _ kind: XcodeResourceKind) throws -> XcodeGroupNode {
        try #require(model.groups.first { $0.kind == kind })
    }

    static func onlyRow(_ model: XcodeModel, _ kind: XcodeResourceKind) throws -> XcodeRow {
        let rows = try group(model, kind).rows
        #expect(rows.count == 1)
        return try #require(rows.first)
    }

    /// `FakeXcode`: le analisi si consumano in ordine (l'ultima resta); l'esecuzione attende
    /// `execution` (al massimo 5 secondi, poi il test fallisce), oppure risponde subito, oppure resta
    /// sospesa fino all'annullamento (al massimo 5 secondi, poi `observedCancellation` registra se è
    /// arrivato).
    final class FakeXcode: XcodeCleanupServing {
        private enum Behavior {
            case waitForGate
            case immediate(XcodeCleanResult)
            case untilCancelled(XcodeCleanResult)
        }

        private struct State {
            var snapshots: [XcodeSnapshot]
            var analysisFailure: (any Error)?
            var behavior = Behavior.waitForGate
            var executeCount = 0
            var receivedJournal: [Bool] = []
            var observedCancellation: [Bool] = []
            var executedKeys: [[String]] = []
        }

        let execution = Gate<XcodeCleanResult>()
        let executionStarted = Gate<Void>()
        private let state: Mutex<State>

        init(_ snapshots: XcodeSnapshot...) {
            state = Mutex(State(snapshots: snapshots))
        }

        var executeCount: Int { state.withLock { $0.executeCount } }
        var receivedJournal: [Bool] { state.withLock { $0.receivedJournal } }
        var observedCancellation: [Bool] { state.withLock { $0.observedCancellation } }
        /// Le chiavi dei candidati di ogni piano eseguito, nell'ordine.
        var executedKeys: [[String]] { state.withLock { $0.executedKeys } }

        func respondImmediately(with result: XcodeCleanResult) { state.withLock { $0.behavior = .immediate(result) } }
        func returnWhenCancelled(_ result: XcodeCleanResult) { state.withLock { $0.behavior = .untilCancelled(result) } }
        func failAnalysis(with error: any Error) { state.withLock { $0.analysisFailure = error } }

        func analyze() async throws -> XcodeSnapshot {
            try state.withLock { state in
                if let failure = state.analysisFailure { throw failure }
                return state.snapshots.count > 1 ? state.snapshots.removeFirst() : state.snapshots.first ?? .empty
            }
        }

        func execute(
            _ plan: XcodeConfirmedPlan,
            progress: (@Sendable (CleanProgress) -> Void)?,
            journal: (any DeletionRecording)?
        ) async -> XcodeCleanResult {
            let behavior = state.withLock { state -> Behavior in
                state.executeCount += 1
                state.receivedJournal.append(journal != nil)
                state.executedKeys.append(plan.candidates.map(\.key))
                return state.behavior
            }
            executionStarted.open()
            for (index, candidate) in plan.candidates.enumerated() {
                progress?(CleanProgress(currentPath: candidate.name, itemsDone: index + 1, itemsTotal: plan.candidates.count, bytesFreed: 0))
            }
            switch behavior {
            case .waitForGate:
                // Se il test non apre `execution`, fallisce allo scadere e l'esecuzione resta vuota.
                return (try? await execution.wait())
                    ?? XcodeCleanResult(historyReport: makeReport(), items: [], freeBytesBefore: 0, freeBytesAfter: 0, warnings: [])
            case .immediate(let result):
                return result
            case .untilCancelled(let result):
                try? await Task.sleep(for: .seconds(5))
                let cancelled = Task.isCancelled
                state.withLock { $0.observedCancellation.append(cancelled) }
                return result
            }
        }
    }

    /// `FakeNavigation`: conta ogni cambio di pagina, come `NavigationCount` del C#.
    final class FakeNavigation: NavigationSpy, XcodeNavigating {
        var navigationCount: Int { events.filter { $0 != "refreshTotal" }.count }

        func showXcode() {
            record("xcode")
        }

        func showXcodeReport(_ report: XcodeReportModel) {
            record("xcodeReport")
        }
    }
}

/// Fotografa il testo d'avanzamento della pagina Xcode quando chiede il resoconto.
@MainActor
private final class ProgressSnapshotNavigation: NavigationSpy, XcodeNavigating {
    weak var model: XcodeModel?
    private(set) var progressAtReport: [String] = []

    func showXcode() {}

    func showXcodeReport(_ report: XcodeReportModel) {
        progressAtReport.append(model?.progressText ?? "")
    }
}
