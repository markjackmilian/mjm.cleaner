/// Un elemento eliminabile. `declaredRoot` serve al PathGuard per il contenimento.
public struct ScanItem: Sendable, Equatable, Hashable {
    public let path: String
    public let sizeBytes: Int64
    public let isDirectory: Bool
    public let declaredRoot: String
    /// Dopo la rimozione di una voce Download selezionata, rimuove i suoi genitori rimasti vuoti
    /// fino alla root dichiarata. È attivo solo nella modalità «Svuota Download» di questa analisi.
    public let pruneEmptyDirectories: Bool

    public init(path: String, sizeBytes: Int64, isDirectory: Bool, declaredRoot: String, pruneEmptyDirectories: Bool = false) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.declaredRoot = declaredRoot
        self.pruneEmptyDirectories = pruneEmptyDirectories
    }
}

public enum ScanErrorKind: Sendable, Equatable {
    case accessDenied
    case inUse
    case notFound
    case notEmpty
    case other
}

public struct ScanError: Sendable, Equatable {
    public let path: String
    public let kind: ScanErrorKind
    public let message: String

    public init(path: String, kind: ScanErrorKind, message: String) {
        self.path = path
        self.kind = kind
        self.message = message
    }
}

public struct GuardExclusion: Sendable, Equatable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct RuleScanOutcome: Sendable, Equatable {
    public let items: [ScanItem]
    public let errors: [ScanError]
    public let exclusions: [GuardExclusion]

    public init(items: [ScanItem], errors: [ScanError], exclusions: [GuardExclusion]) {
        self.items = items
        self.errors = errors
        self.exclusions = exclusions
    }
}

public struct CategoryScanResult: Sendable, Equatable {
    public let categoryId: String
    public let items: [ScanItem]
    public let totalBytes: Int64
    public let errors: [ScanError]
    public let exclusions: [GuardExclusion]

    public init(categoryId: String, items: [ScanItem], totalBytes: Int64, errors: [ScanError], exclusions: [GuardExclusion]) {
        self.categoryId = categoryId
        self.items = items
        self.totalBytes = totalBytes
        self.errors = errors
        self.exclusions = exclusions
    }
}

public struct ScanProgress: Sendable, Equatable {
    public let categoryId: String
    public let currentPath: String
    public let itemsFound: Int
    public let bytesFound: Int64

    public init(categoryId: String, currentPath: String, itemsFound: Int, bytesFound: Int64) {
        self.categoryId = categoryId
        self.currentPath = currentPath
        self.itemsFound = itemsFound
        self.bytesFound = bytesFound
    }
}
