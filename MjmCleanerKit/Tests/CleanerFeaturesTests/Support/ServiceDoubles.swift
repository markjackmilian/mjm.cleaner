import CleanerCore
import CleanerFeatures
import Foundation
import Synchronization

/// Doppi dei servizi del Core condivisi dai test dei modelli. Lo stato sta in `Mutex`: i servizi
/// sono `Sendable` e vengono chiamati anche fuori dal main actor.

final class FakeSettingsStore: SettingsStoring {
    private struct State {
        var current: CleanerSettings
        var saves = 0
        var failure: (any Error)?
    }

    private let state: Mutex<State>

    init(_ initial: CleanerSettings = CleanerSettings()) {
        state = Mutex(State(current: initial))
    }

    var current: CleanerSettings { state.withLock { $0.current } }
    var saves: Int { state.withLock { $0.saves } }

    func failSaves(with error: any Error) {
        state.withLock { $0.failure = error }
    }

    func load() -> CleanerSettings {
        state.withLock { $0.current }
    }

    func save(_ settings: CleanerSettings) throws {
        try state.withLock { state in
            state.saves += 1
            if let failure = state.failure { throw failure }
            state.current = settings
        }
    }
}

/// Registra in `events` l'ordine delle operazioni ("save", "total"), condiviso col log di sessione.
final class FakeHistory: HistoryStoring {
    private struct State {
        var sessions: [CleanSessionSummary] = []
        var total: Int64 = 0
        var saved: [CleanReport] = []
        var saveFailure: (any Error)?
        var readFailure: (any Error)?
    }

    let events: Recorder<String>
    private let state = Mutex(State())

    init(events: Recorder<String> = Recorder()) {
        self.events = events
    }

    var saves: Int { state.withLock { $0.saved.count } }
    var saved: [CleanReport] { state.withLock { $0.saved } }

    func setSessions(_ sessions: [CleanSessionSummary]) { state.withLock { $0.sessions = sessions } }
    func setTotal(_ total: Int64) { state.withLock { $0.total = total } }
    func failSaves(with error: any Error) { state.withLock { $0.saveFailure = error } }
    func failReads(with error: any Error) { state.withLock { $0.readFailure = error } }

    func initialize() async throws {}

    func save(_ report: CleanReport) async throws -> Int64 {
        events.append("save")
        return try state.withLock { state in
            state.saved.append(report)
            if let failure = state.saveFailure { throw failure }
            return Int64(state.saved.count)
        }
    }

    func sessions(limit: Int) async throws -> [CleanSessionSummary] {
        try state.withLock { state in
            if let failure = state.readFailure { throw failure }
            return Array(state.sessions.prefix(limit))
        }
    }

    func totalBytesFreed() async throws -> Int64 {
        events.append("total")
        return try state.withLock { state in
            if let failure = state.readFailure { throw failure }
            return state.total
        }
    }
}

/// Log di sessione finto. Con `journalDirectory` i diari sono veri (`SessionLogWriter` su una
/// cartella temporanea), perché `PendingJournal` si crea solo dal Core; senza, `openJournal`
/// restituisce `nil` come quando la cartella dei log non è scrivibile.
final class FakeSessionLog: SessionLogWriting {
    private struct State {
        var written: [(sessionId: Int64, report: CleanReport)] = []
        var discarded: [String] = []
        var writeFailure: (any Error)?
    }

    let events: Recorder<String>
    private let journals: SessionLogWriter?
    private let state = Mutex(State())

    init(events: Recorder<String> = Recorder(), journalDirectory: String? = nil) {
        self.events = events
        journals = journalDirectory.map {
            SessionLogWriter(fileSystem: LocalFileSystem(), paths: AppPaths(supportDirectory: $0))
        }
    }

    var writes: Int { state.withLock { $0.written.count } }
    var written: [(sessionId: Int64, report: CleanReport)] { state.withLock { $0.written } }
    var discarded: [String] { state.withLock { $0.discarded } }

    func failWrites(with error: any Error) {
        state.withLock { $0.writeFailure = error }
    }

    func write(sessionId: Int64, report: CleanReport) async throws {
        events.append("write")
        try state.withLock { state in
            if let failure = state.writeFailure { throw failure }
            state.written.append((sessionId, report))
        }
    }

    func openJournal(startedAt: Date) -> PendingJournal? {
        events.append("open")
        return journals?.openJournal(startedAt: startedAt)
    }

    func discard(_ journal: PendingJournal) {
        events.append("discard")
        state.withLock { $0.discarded.append(journal.path) }
        journals?.discard(journal)
    }
}

/// Analisi finta: restituisce `results`, lancia `failure` o, con `waitsForCancellation`, resta
/// sospesa finché il task non viene annullato e allora lancia `CancellationError` come `ScanEngine`.
/// L'attesa dura al massimo 5 secondi: se l'annullamento non arriva il test fallisce invece di bloccarsi.
final class FakeScan: ScanPerforming {
    private struct State {
        var results: [CategoryScanResult] = []
        var failure: (any Error)?
        var waitsForCancellation = false
        var progress: [ScanProgress] = []
        var scanned: [[String]] = []
    }

    let started = Gate<Void>()
    private let state = Mutex(State())

    var scannedCategoryIds: [[String]] { state.withLock { $0.scanned } }

    func respond(with results: [CategoryScanResult], progress: [ScanProgress] = []) {
        state.withLock {
            $0.results = results
            $0.progress = progress
        }
    }

    func fail(with error: any Error) { state.withLock { $0.failure = error } }
    func waitForCancellation() { state.withLock { $0.waitsForCancellation = true } }

    func scan(_ categories: [CleanupCategory], progress: (@Sendable (ScanProgress) -> Void)?) async throws -> [CategoryScanResult] {
        let current = state.withLock { state -> State in
            state.scanned.append(categories.map(\.id))
            return state
        }
        started.open()
        for update in current.progress {
            progress?(update)
        }
        if current.waitsForCancellation {
            try await Task.sleep(for: .seconds(5))
        }
        if let failure = current.failure { throw failure }
        return current.results
    }
}

/// Pulizia finta: registra selezioni e diario, segnala un avanzamento per elemento e restituisce
/// `result`. Con `waitsForCancellation` resta sospesa finché il task non viene annullato (al massimo
/// 5 secondi) e poi restituisce `result` come resoconto parziale, come `CleanEngine`;
/// `observedCancellation` dice se l'annullamento è arrivato.
final class FakeClean: CleanPerforming {
    private struct State {
        var result = makeReport()
        var waitsForCancellation = false
        var selections: [[CategorySelection]] = []
        var receivedJournal: [Bool] = []
        var observedCancellation: [Bool] = []
    }

    let started = Gate<Void>()
    private let state = Mutex(State())

    var selections: [[CategorySelection]] { state.withLock { $0.selections } }
    var receivedJournal: [Bool] { state.withLock { $0.receivedJournal } }
    var observedCancellation: [Bool] { state.withLock { $0.observedCancellation } }

    func respond(with result: CleanReport) { state.withLock { $0.result = result } }
    func waitForCancellation() { state.withLock { $0.waitsForCancellation = true } }

    func clean(
        _ selections: [CategorySelection],
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> CleanReport {
        let current = state.withLock { state -> State in
            state.selections.append(selections)
            state.receivedJournal.append(journal != nil)
            return state
        }
        started.open()

        let items = selections.flatMap(\.items)
        for (index, item) in items.enumerated() {
            journal?.recordDeleted(item.path)
            progress?(CleanProgress(currentPath: item.path, itemsDone: index + 1, itemsTotal: items.count, bytesFreed: 0))
        }
        if current.waitsForCancellation {
            try? await Task.sleep(for: .seconds(5))
            let cancelled = Task.isCancelled
            state.withLock { $0.observedCancellation.append(cancelled) }
        }
        return current.result
    }
}

final class FakeRunningApps: RunningAppsProbing {
    private let names: [String]

    init(_ names: [String] = []) {
        self.names = names
    }

    func affectedApps(_ paths: [String]) async -> [String] {
        names
    }
}

/// Docker finto: le analisi si consumano in ordine (l'ultima resta), l'esecuzione restituisce il
/// risultato o lancia l'errore preparati con `respond(with:)`.
final class FakeDocker: DockerCleanupServing {
    private struct State {
        var analyses: [Result<DockerAnalysis, any Error>] = []
        var executeResult: Result<DockerCleanResult, any Error> = .success(DockerCleanResult(
            report: makeReport(), before: .empty, after: .empty, daemonLost: false))
        var disk = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil)
        var analyzedRoots: [[String]] = []
        var executed: [[DockerCandidate]] = []
    }

    private let state = Mutex(State())

    var analyzedRoots: [[String]] { state.withLock { $0.analyzedRoots } }
    var executed: [[DockerCandidate]] { state.withLock { $0.executed } }

    func enqueue(_ analysis: Result<DockerAnalysis, any Error>) { state.withLock { $0.analyses.append(analysis) } }
    func respond(with result: Result<DockerCleanResult, any Error>) { state.withLock { $0.executeResult = result } }
    func setDiskAfter(_ disk: DockerDiskUsage) { state.withLock { $0.disk = disk } }

    func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let next = state.withLock { state -> Result<DockerAnalysis, any Error>? in
            state.analyzedRoots.append(projectRoots)
            return state.analyses.count > 1 ? state.analyses.removeFirst() : state.analyses.first
        }
        guard let next else { throw DockerUnavailableError("nessuna analisi preparata") }
        return try next.get()
    }

    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        let result = state.withLock { state -> Result<DockerCleanResult, any Error> in
            state.executed.append(selected)
            return state.executeResult
        }
        for (index, candidate) in selected.enumerated() {
            progress?(CleanProgress(currentPath: candidate.displayName, itemsDone: index + 1, itemsTotal: selected.count, bytesFreed: 0))
        }
        return try result.get()
    }

    func measureDisk() async throws -> DockerDiskUsage {
        state.withLock { $0.disk }
    }
}

/// Xcode inattivo, per i test che non aprono la pagina Xcode.
struct IdleXcode: XcodeCleanupServing {
    func analyze() async throws -> XcodeSnapshot { .empty }

    func execute(_ plan: XcodeConfirmedPlan, progress: (@Sendable (CleanProgress) -> Void)?, journal: (any DeletionRecording)?) async -> XcodeCleanResult {
        XcodeCleanResult(historyReport: makeReport(), items: [], freeBytesBefore: nil, freeBytesAfter: nil, warnings: [])
    }
}

/// Un `AppEnvironment` di soli doppi, con la home finta `/Users/tester`.
func makeEnvironment(
    scan: any ScanPerforming = FakeScan(),
    clean: any CleanPerforming = FakeClean(),
    history: any HistoryStoring = FakeHistory(),
    sessionLog: any SessionLogWriting = FakeSessionLog(),
    settings: any SettingsStoring = FakeSettingsStore(),
    runningApps: any RunningAppsProbing = FakeRunningApps(),
    docker: any DockerCleanupServing = FakeDocker(),
    xcode: any XcodeCleanupServing = IdleXcode()
) throws -> AppEnvironment {
    AppEnvironment(
        scan: scan,
        clean: clean,
        history: history,
        sessionLog: sessionLog,
        settings: settings,
        runningApps: runningApps,
        docker: docker,
        xcode: xcode,
        paths: AppPaths(supportDirectory: "/Users/tester/Library/Application Support/com.mjm.cleaner"),
        clock: FixedWallClock(now: Date(timeIntervalSince1970: 1_790_000_000)),
        expander: try PathExpander(homeDirectory: "/Users/tester", tempDirectory: "/private/var/folders/zz/T"))
}
