import CleanerCore

/// Il servizio Docker visto dalla pagina. In C# la pagina usava la classe concreta
/// `DockerCleanupService` e nessun test la esercitava; il protocollo permette di verificare la
/// pagina con un doppio, senza toccare il Core.
public protocol DockerCleanupServing: Sendable {
    func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis
    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult
    /// Il disco virtuale del motore dell'analisi dopo la pulizia; `nil` se quel motore non ne ha
    /// uno da misurare.
    func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage?
}

extension DockerCleanupService: DockerCleanupServing {}
