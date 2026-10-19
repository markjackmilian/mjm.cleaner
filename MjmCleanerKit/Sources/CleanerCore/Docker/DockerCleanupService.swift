/// Il motore su cui si è fatta l'analisi: il contesto letto al suo inizio e il daemon che ha
/// risposto lì. L'esecuzione resta su quel contesto e rifiuta un daemon diverso.
public struct DockerTarget: Sendable, Equatable {
    public let context: DockerContext
    public let engine: DockerEngine

    public init(context: DockerContext, engine: DockerEngine) {
        self.context = context
        self.engine = engine
    }
}

/// `engine`: il motore che ha risposto. `context`: il contesto a cui l'analisi è rimasta fissata.
/// `disk`: il disco virtuale del motore, `nil` per un motore che non ne ha uno da misurare
/// (`DiskUsageProbe.measure(for:)`).
public struct DockerAnalysis: Sendable, Equatable {
    public let engine: DockerEngine
    public let context: DockerContext
    public let snapshot: DockerSnapshot
    public let candidates: [DockerCandidate]
    public let disk: DockerDiskUsage?

    public init(engine: DockerEngine, context: DockerContext, snapshot: DockerSnapshot, candidates: [DockerCandidate], disk: DockerDiskUsage?) {
        self.engine = engine
        self.context = context
        self.snapshot = snapshot
        self.candidates = candidates
        self.disk = disk
    }

    /// Il bersaglio da consegnare all'esecuzione.
    public var target: DockerTarget {
        DockerTarget(context: context, engine: engine)
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

    /// L'analisi resta sul contesto attivo al suo inizio: ogni comando porta `--context`, e un
    /// cambio di contesto a metà non mescola due motori. «Non installato» e un contesto illeggibile
    /// risalgono così come sono; un daemon che non risponde diventa un errore che nomina il motore
    /// di quel contesto: l'utente sa quale avviare.
    @concurrent
    public func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let context = try await contexts.activeContext()
        let pinned = try collector.pinned(to: context.name)

        do {
            return try await analyzeRunningDaemon(projectRoots, pinned, context)
        } catch let error as DockerUnavailableError where error.reason == .notRunning {
            throw DockerUnavailableError(contexts.notRunningMessage(for: context))
        }
    }

    /// L'esecuzione resta sul bersaglio dell'analisi. Un daemon che non risponde prima di ogni
    /// cancellazione (quello perso a metà finisce nel resoconto) diventa l'errore che nomina il
    /// motore del contesto analizzato, anche se il contesto attivo ora è un altro, e chiede di
    /// premere di nuovo «Elimina» dopo averlo avviato.
    public func execute(
        _ selected: [DockerCandidate],
        on target: DockerTarget,
        progress: (@Sendable (CleanProgress) -> Void)?
    ) async throws -> DockerCleanResult {
        do {
            return try await executor.execute(selected, on: target, progress: progress)
        } catch let error as DockerUnavailableError where error.reason == .notRunning {
            throw DockerUnavailableError(contexts.notRunningForDeletionMessage(for: target.context))
        }
    }

    /// Il disco del motore dell'analisi dopo la pulizia; `nil` se quel motore non ne ha uno da misurare.
    public func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        try await disk.measure(for: engine)
    }

    /// Raccolta da Docker e ricerca nei progetti procedono in parallelo: sono indipendenti, e la
    /// seconda attraversa il disco mentre la prima attende la CLI. Le attività figlie di `async let`
    /// girano sull'executor globale, mai su quello del chiamante (`Task.Run` nel C#).
    @concurrent
    private func analyzeRunningDaemon(
        _ projectRoots: [String],
        _ pinned: DockerInventoryCollector,
        _ context: DockerContext
    ) async throws -> DockerAnalysis {
        let engine = try await pinned.checkDaemon()

        async let references = scanner.scan(projectRoots)
        async let usage = disk.measure(for: engine)
        let snapshot = try await pinned.collect()

        return DockerAnalysis(
            engine: engine,
            context: context,
            snapshot: snapshot,
            candidates: try DockerClassifier.classify(snapshot, try await references),
            disk: try await usage)
    }
}
