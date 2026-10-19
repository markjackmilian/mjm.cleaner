/// `engine`: il motore che ha risposto. `disk`: il suo disco virtuale, `nil` per un motore che non
/// ne ha uno da misurare (`DiskUsageProbe.measure(for:)`).
public struct DockerAnalysis: Sendable, Equatable {
    public let engine: DockerEngine
    public let snapshot: DockerSnapshot
    public let candidates: [DockerCandidate]
    public let disk: DockerDiskUsage?

    public init(engine: DockerEngine, snapshot: DockerSnapshot, candidates: [DockerCandidate], disk: DockerDiskUsage?) {
        self.engine = engine
        self.snapshot = snapshot
        self.candidates = candidates
        self.disk = disk
    }
}

/// Il flusso completo per l'interfaccia: analisi in sola lettura, esecuzione, misura del disco.
public struct DockerCleanupService: Sendable {
    private let collector: DockerInventoryCollector
    private let scanner: ProjectReferenceScanner
    private let disk: DiskUsageProbe
    private let executor: DockerCleanExecutor
    private let contexts: DockerContextReader

    public init(
        collector: DockerInventoryCollector,
        scanner: ProjectReferenceScanner,
        disk: DiskUsageProbe,
        executor: DockerCleanExecutor,
        contexts: DockerContextReader
    ) {
        self.collector = collector
        self.scanner = scanner
        self.disk = disk
        self.executor = executor
        self.contexts = contexts
    }

    /// Un daemon che non risponde diventa un errore che nomina il motore del contesto attivo:
    /// l'utente sa quale avviare. «Non installato» resta com'è.
    @concurrent
    public func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        do {
            return try await analyzeRunningDaemon(projectRoots)
        } catch let error as DockerUnavailableError where error.reason == .notRunning {
            throw DockerUnavailableError(await contexts.notRunningMessage())
        }
    }

    public func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        try await executor.execute(selected, progress: progress)
    }

    /// Il disco del motore dell'analisi dopo la pulizia; `nil` se quel motore non ne ha uno da misurare.
    public func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        try await disk.measure(for: engine)
    }

    /// Raccolta da Docker e ricerca nei progetti procedono in parallelo: sono indipendenti, e la
    /// seconda attraversa il disco mentre la prima attende la CLI. Le attività figlie di `async let`
    /// girano sull'executor globale, mai su quello del chiamante (`Task.Run` nel C#).
    @concurrent
    private func analyzeRunningDaemon(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let engine = try await collector.checkDaemon()

        async let references = scanner.scan(projectRoots)
        async let usage = disk.measure(for: engine)
        let snapshot = try await collector.collect()

        return DockerAnalysis(
            engine: engine,
            snapshot: snapshot,
            candidates: try DockerClassifier.classify(snapshot, try await references),
            disk: try await usage)
    }
}
