/// Il motore che risponde dietro la CLI `docker`, riconosciuto dall'`OperatingSystem` del daemon
/// («Docker Desktop», «OrbStack»; Colima, per esempio, riporta la distribuzione della sua macchina
/// virtuale). Quale motore si pulisce lo decide il contesto attivo della CLI: qui lo si riconosce
/// soltanto, per i testi e per il disco virtuale.
public enum DockerEngineKind: Sendable, Equatable {
    case dockerDesktop
    case orbStack
    case other
}

public struct DockerEngine: Sendable, Equatable {
    public let kind: DockerEngineKind
    /// «Docker Desktop», «OrbStack» oppure «Docker» per ogni altro motore.
    public let displayName: String
    /// L'`OperatingSystem` del daemon così com'è; può essere vuoto.
    public let operatingSystem: String
    public let serverVersion: String
    /// L'`ID` del daemon, persistente per `dockerd`: distingue due daemon dello stesso tipo dietro
    /// lo stesso contesto (`default` segue `/var/run/docker.sock`, che il motore avviato per ultimo
    /// riscrive). Vuoto se il daemon non lo riporta.
    public let id: String

    public init(serverVersion: String, operatingSystem: String, id: String = "") {
        let kind = Self.kind(named: operatingSystem)
        self.kind = kind
        self.serverVersion = serverVersion
        self.operatingSystem = operatingSystem
        self.id = id
        displayName = switch kind {
        case .dockerDesktop: "Docker Desktop"
        case .orbStack: "OrbStack"
        case .other: "Docker"
        }
    }

    /// Il motore che porta questo nome. Il confronto è sull'intero valore, senza distinguere
    /// maiuscole e minuscole: un testo più lungo che contiene «OrbStack» non basta. Vale per
    /// l'`OperatingSystem` del daemon e per la descrizione di un contesto.
    static func kind(named name: String) -> DockerEngineKind {
        if PathText.equalsIgnoringCase(name, "Docker Desktop") { return .dockerDesktop }
        if PathText.equalsIgnoringCase(name, "OrbStack") { return .orbStack }
        return .other
    }
}
