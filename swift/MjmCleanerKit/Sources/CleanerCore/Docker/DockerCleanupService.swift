/// `serverVersion`: versione del daemon che ha risposto.
public struct DockerAnalysis: Sendable, Equatable {
    public let serverVersion: String
    public let snapshot: DockerSnapshot
    public let candidates: [DockerCandidate]
    public let disk: DockerDiskUsage

    public init(serverVersion: String, snapshot: DockerSnapshot, candidates: [DockerCandidate], disk: DockerDiskUsage) {
        self.serverVersion = serverVersion
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

    public init(collector: DockerInventoryCollector, scanner: ProjectReferenceScanner, disk: DiskUsageProbe, executor: DockerCleanExecutor) {
        self.collector = collector
        self.scanner = scanner
        self.disk = disk
        self.executor = executor
    }

    /// Raccolta da Docker e ricerca nei progetti procedono in parallelo: sono indipendenti, e la
    /// seconda attraversa il disco mentre la prima attende la CLI. Le attività figlie di `async let`
    /// girano sull'executor globale, mai su quello del chiamante (`Task.Run` nel C#).
    @concurrent
    public func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let version = try await collector.checkDaemon()

        async let references = scanner.scan(projectRoots)
        async let usage = disk.measure()
        let snapshot = try await collector.collect()

        return DockerAnalysis(
            serverVersion: version,
            snapshot: snapshot,
            candidates: try DockerClassifier.classify(snapshot, try await references),
            disk: try await usage)
    }

    public func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        try await executor.execute(selected, progress: progress)
    }

    public func measureDisk() async throws -> DockerDiskUsage {
        try await disk.measure()
    }
}
