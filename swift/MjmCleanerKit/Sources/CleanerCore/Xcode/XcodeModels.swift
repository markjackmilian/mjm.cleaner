import Foundation

public enum XcodeResourceKind: Sendable, Equatable, Hashable {
    case derivedData
    case deviceSupport
    case device
    case runtime
}

/// Una riga dell'inventario Xcode. Le proprietà sono `var` perché i `with` del C# diventano copie
/// modificate: la semantica di valore garantisce che la copia non tocchi l'originale.
public struct XcodeCandidate: Sendable, Equatable {
    public var key: String
    public var kind: XcodeResourceKind
    public var name: String
    public var path: String?
    public var cliId: String?
    public var runtimeIdentifier: String?
    public var build: String?
    public var state: String?
    public var sizeBytes: Int64?
    public var blockReason: String?
    public var dependencies: [String]?

    public init(
        key: String,
        kind: XcodeResourceKind,
        name: String,
        path: String? = nil,
        cliId: String? = nil,
        runtimeIdentifier: String? = nil,
        build: String? = nil,
        state: String? = nil,
        sizeBytes: Int64? = nil,
        blockReason: String? = nil,
        dependencies: [String]? = nil
    ) {
        self.key = key
        self.kind = kind
        self.name = name
        self.path = path
        self.cliId = cliId
        self.runtimeIdentifier = runtimeIdentifier
        self.build = build
        self.state = state
        self.sizeBytes = sizeBytes
        self.blockReason = blockReason
        self.dependencies = dependencies
    }

    public var canSelect: Bool { blockReason == nil }

    public var dependentDeviceKeys: [String] { dependencies ?? [] }
}

public enum XcodeInventoryWarningKind: Sendable, Equatable {
    case completenessFailure
    case advisory
}

public struct XcodeInventoryWarning: Sendable, Equatable {
    public let resourceGroup: XcodeResourceKind
    public let message: String
    /// Prudente per chi non classifica il proprio avviso: come in C#, il default è un difetto di
    /// completezza, che blocca la verifica di quel gruppo.
    public let kind: XcodeInventoryWarningKind

    public init(resourceGroup: XcodeResourceKind, message: String, kind: XcodeInventoryWarningKind = .completenessFailure) {
        self.resourceGroup = resourceGroup
        self.message = message
        self.kind = kind
    }

    public static func completenessFailure(_ group: XcodeResourceKind, _ message: String) -> XcodeInventoryWarning {
        XcodeInventoryWarning(resourceGroup: group, message: message, kind: .completenessFailure)
    }

    public static func advisory(_ group: XcodeResourceKind, _ message: String) -> XcodeInventoryWarning {
        XcodeInventoryWarning(resourceGroup: group, message: message, kind: .advisory)
    }
}

public struct XcodeSnapshot: Sendable, Equatable {
    public var candidates: [XcodeCandidate]
    public var warnings: [XcodeInventoryWarning]
    public var fileInventory: XcodeFileInventory

    public init(candidates: [XcodeCandidate], warnings: [XcodeInventoryWarning], fileInventory: XcodeFileInventory = .empty) {
        self.candidates = candidates
        self.warnings = warnings
        self.fileInventory = fileInventory
    }

    public static let empty = XcodeSnapshot(candidates: [], warnings: [])
}

/// Metadati portabili catturati insieme a una cartella validata, per riverificarla subito prima di
/// eliminarla. Le date valgono `nil` dove il C# aveva `default(DateTime)`, cioè «non rilevata».
public struct XcodeFileIdentity: Sendable, Equatable {
    public let canonicalPath: String
    public let isDirectory: Bool
    public let creationTime: Date?
    public let lastWriteTime: Date?
    public let logicalSizeBytes: Int64?

    public init(canonicalPath: String, isDirectory: Bool, creationTime: Date?, lastWriteTime: Date?, logicalSizeBytes: Int64?) {
        self.canonicalPath = canonicalPath
        self.isDirectory = isDirectory
        self.creationTime = creationTime
        self.lastWriteTime = lastWriteTime
        self.logicalSizeBytes = logicalSizeBytes
    }
}

public struct XcodeFileEntry: Sendable, Equatable {
    public let item: ScanItem
    public let identity: XcodeFileIdentity

    public init(item: ScanItem, identity: XcodeFileIdentity) {
        self.item = item
        self.identity = identity
    }
}

public enum XcodeItemOutcome: Sendable, Equatable {
    case deleted
    case skipped
    case failed
    case uncertain
}

public struct XcodeItemResult: Sendable, Equatable {
    public let candidate: XcodeCandidate
    public let outcome: XcodeItemOutcome
    public let reason: String
    public let verifiedEstimatedBytes: Int64?

    public init(candidate: XcodeCandidate, outcome: XcodeItemOutcome, reason: String, verifiedEstimatedBytes: Int64?) {
        self.candidate = candidate
        self.outcome = outcome
        self.reason = reason
        self.verifiedEstimatedBytes = verifiedEstimatedBytes
    }
}

public struct XcodeCleanResult: Sendable, Equatable {
    public let historyReport: CleanReport
    public let items: [XcodeItemResult]
    public let freeBytesBefore: Int64?
    public let freeBytesAfter: Int64?
    public let warnings: [String]

    public init(historyReport: CleanReport, items: [XcodeItemResult], freeBytesBefore: Int64?, freeBytesAfter: Int64?, warnings: [String]) {
        self.historyReport = historyReport
        self.items = items
        self.freeBytesBefore = freeBytesBefore
        self.freeBytesAfter = freeBytesAfter
        self.warnings = warnings
    }
}

/// Mappa immutabile chiave del candidato → cartella validata. Chiavi confrontate in modo ordinale
/// (`StringComparer.Ordinal`): sui byte UTF-8, non con l'equivalenza canonica di `String`.
/// Conserva l'ordine di inserimento; a parità di chiave vale la prima voce (i chiamanti non ne
/// passano mai due: lo scanner le scarta e `XcodeSelection` parte da chiavi già verificate).
public struct XcodeFileInventory: Sendable, Equatable {
    public static let empty = XcodeFileInventory([])

    public let keys: [String]
    private let entries: [[UInt8]: XcodeFileEntry]

    public init(_ items: [(key: String, entry: XcodeFileEntry)]) {
        var keys: [String] = []
        var entries: [[UInt8]: XcodeFileEntry] = [:]
        for item in items {
            let ordinal = XcodeText.ordinalKey(item.key)
            if entries[ordinal] != nil { continue }
            entries[ordinal] = item.entry
            keys.append(item.key)
        }
        self.keys = keys
        self.entries = entries
    }

    public subscript(key: String) -> XcodeFileEntry? {
        entries[XcodeText.ordinalKey(key)]
    }

    public var count: Int { keys.count }

    public var values: [XcodeFileEntry] { keys.compactMap { self[$0] } }

    public func contains(_ key: String) -> Bool { self[key] != nil }
}

/// Equivalente di `ArgumentException`: un inventario o una selezione che il chiamante non doveva
/// produrre. Il testo è quello del C# (in inglese, senza il suffisso «(Parameter '…')» di .NET).
public struct XcodeArgumentError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Equivalente di `InvalidOperationException`: una conferma che non può procedere.
public struct XcodeOperationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Equivalente di `XcodeUnavailableException`: `xcrun` assente o non avviabile.
public struct XcodeUnavailableError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// `IXcodeCli`: solo comandi d'inventario in lettura e rimozioni mirate per UUID.
public protocol XcodeCliInvoking: Sendable {
    func readInventory() async throws -> XcodeSnapshot
    func deleteDevice(_ uuid: String) async throws -> ProcessResult
    func deleteRuntime(_ uuid: String) async throws -> ProcessResult
}

/// `IXcodeInventoryCollector`: il confine verso l'applicazione.
public protocol XcodeInventoryCollecting: Sendable {
    func collect() async throws -> XcodeSnapshot
}
