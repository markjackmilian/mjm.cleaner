public enum DockerVerdict: Sendable, Equatable, Hashable {
    case keep
    case delete
    case propose
    case ask
}

public enum DockerResourceKind: Sendable, Equatable, Hashable {
    case image
    case volume
    case buildCache
}

/// Da dove viene un'immagine. Con il containerd image store `RepoDigests` è valorizzato anche per
/// le immagini costruite in locale: l'origine si legge da `.Identity`.
public enum ImageOrigin: Sendable, Equatable, Hashable {
    case unknown
    case pulled
    case built
}

/// Un container, anche fermo: un container fermo tiene in uso immagine e volumi quanto uno attivo.
public struct DockerContainer: Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let imageId: String
    public let state: String
    public let exitCode: Int
    public let volumeNames: [String]
    public let labels: [String: String]

    public init(id: String, name: String, imageId: String, state: String, exitCode: Int, volumeNames: [String], labels: [String: String]) {
        self.id = id
        self.name = name
        self.imageId = imageId
        self.state = state
        self.exitCode = exitCode
        self.volumeNames = volumeNames
        self.labels = labels
    }
}

public struct DockerImage: Sendable, Equatable, Hashable {
    /// Il segnaposto che Docker mostra al posto di un tag assente.
    static let noTag = "<none>:<none>"

    public let id: String
    public let repoTags: [String]
    public let repoDigests: [String]
    public let sizeBytes: Int64
    public let uniqueSizeBytes: Int64?
    public let labels: [String: String]
    public let origin: ImageOrigin

    public init(
        id: String,
        repoTags: [String],
        repoDigests: [String],
        sizeBytes: Int64,
        uniqueSizeBytes: Int64?,
        labels: [String: String],
        origin: ImageOrigin
    ) {
        self.id = id
        self.repoTags = repoTags
        self.repoDigests = repoDigests
        self.sizeBytes = sizeBytes
        self.uniqueSizeBytes = uniqueSizeBytes
        self.labels = labels
        self.origin = origin
    }

    /// Senza tag, o con il solo segnaposto "<none>:<none>".
    public var isDangling: Bool { repoTags.allSatisfy { $0 == Self.noTag } }

    public var names: [ImageName] { repoTags.filter { $0 != Self.noTag }.map(ImageName.parse) }

    public var displayName: String { repoTags.first { $0 != Self.noTag } ?? Self.shortId(id) }

    /// Le prime 12 cifre dell'identificativo, senza "sha256:". La lunghezza si conta in unità
    /// UTF-16 come `string.Length` (gli ID di Docker sono esadecimali ASCII).
    public static func shortId(_ id: String) -> String {
        let hex = DockerText.hasPrefix(id, "sha256:") ? String(decoding: id.utf8.dropFirst(7), as: UTF8.self) : id
        return hex.utf16.count > 12 ? String(decoding: Array(hex.utf16.prefix(12)), as: UTF16.self) : hex
    }
}

public struct DockerVolume: Sendable, Equatable, Hashable {
    public let name: String
    public let labels: [String: String]
    public let sizeBytes: Int64?

    public init(name: String, labels: [String: String], sizeBytes: Int64?) {
        self.name = name
        self.labels = labels
        self.sizeBytes = sizeBytes
    }
}

/// Una riga di `docker system df`: "Images", "Containers", "Local Volumes", "Build Cache".
public struct DockerDfEntry: Sendable, Equatable, Hashable {
    public let type: String
    public let sizeBytes: Int64
    public let reclaimableBytes: Int64

    public init(type: String, sizeBytes: Int64, reclaimableBytes: Int64) {
        self.type = type
        self.sizeBytes = sizeBytes
        self.reclaimableBytes = reclaimableBytes
    }
}

public struct DockerDfSummary: Sendable, Equatable, Hashable {
    public static let imagesType = "Images"
    public static let volumesType = "Local Volumes"
    public static let buildCacheType = "Build Cache"

    public static let empty = DockerDfSummary(entries: [])

    public let entries: [DockerDfEntry]

    public init(entries: [DockerDfEntry]) {
        self.entries = entries
    }

    public var images: Int64 { sizeOf(Self.imagesType) }
    public var volumes: Int64 { sizeOf(Self.volumesType) }
    public var buildCache: Int64 { sizeOf(Self.buildCacheType) }
    public var total: Int64 { entries.reduce(0) { $0 + $1.sizeBytes } }

    public func sizeOf(_ type: String) -> Int64 {
        entries.first { $0.type == type }?.sizeBytes ?? 0
    }
}

/// Tutto ciò che la classificazione deve sapere, raccolto una volta sola. Privo di dipendenze dalla
/// CLI: le regole lo leggono senza poter lanciare comandi né toccare il disco. I campi sono `var`
/// per replicare l'espressione `with` dei record C# nei test: la struct resta un valore.
///
/// `existingComposeProjects`: progetti compose la cui cartella esiste ancora, verificato dal
/// collector (la verifica su disco è I/O, quindi non può stare nelle regole).
public struct DockerSnapshot: Sendable, Equatable {
    public var containers: [DockerContainer]
    public var images: [DockerImage]
    public var volumes: [DockerVolume]
    public var df: DockerDfSummary
    public var existingComposeProjects: Set<String>

    public init(
        containers: [DockerContainer],
        images: [DockerImage],
        volumes: [DockerVolume],
        df: DockerDfSummary,
        existingComposeProjects: Set<String>
    ) {
        self.containers = containers
        self.images = images
        self.volumes = volumes
        self.df = df
        self.existingComposeProjects = existingComposeProjects
    }
}

/// Esito della classificazione di una singola risorsa: cosa fare, perché, e quanto costa ricrearla.
public struct DockerCandidate: Sendable, Equatable, Hashable {
    public let kind: DockerResourceKind
    public let id: String
    public let displayName: String
    public let sizeBytes: Int64?
    public let verdict: DockerVerdict
    public let ruleId: String
    public let reason: String
    public let cost: String

    public init(
        kind: DockerResourceKind,
        id: String,
        displayName: String,
        sizeBytes: Int64?,
        verdict: DockerVerdict,
        ruleId: String,
        reason: String,
        cost: String
    ) {
        self.kind = kind
        self.id = id
        self.displayName = displayName
        self.sizeBytes = sizeBytes
        self.verdict = verdict
        self.ruleId = ruleId
        self.reason = reason
        self.cost = cost
    }

    /// Solo le voci sicure (DELETE) partono selezionate. PROPOSE e ASK richiedono un gesto esplicito
    /// dell'utente; KEEP non è mai selezionabile.
    public var selectedByDefault: Bool { verdict == .delete }
}

/// Un'immagine citata in un file di progetto. `tag` nullo: il file nomina solo il repository.
public struct ImageReference: Sendable, Equatable, Hashable {
    public let repository: String
    public let tag: String?
    public let file: String
    public let line: Int

    public init(repository: String, tag: String?, file: String, line: Int) {
        self.repository = repository
        self.tag = tag
        self.file = file
        self.line = line
    }
}

/// Ciò che la ricerca nei progetti ha trovato: immagini citate e progetti compose esistenti.
public struct ProjectReferences: Sendable, Equatable {
    public static let empty = ProjectReferences(images: [], composeProjects: [])

    public let images: [ImageReference]
    public let composeProjects: Set<String>

    public init(images: [ImageReference], composeProjects: Set<String>) {
        self.images = images
        self.composeProjects = composeProjects
    }
}
