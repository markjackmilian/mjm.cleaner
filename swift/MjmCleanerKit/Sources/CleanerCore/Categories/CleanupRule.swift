import Foundation

public enum ScanMode: Sendable, Equatable {
    /// Svuota il contenuto della root mantenendo la root stessa.
    case clearContents
    /// Cerca ricorsivamente cartelle il cui nome corrisponde ai pattern.
    case matchingDirs
    /// Cerca file per pattern, età e dimensione.
    case matchingFiles
}

public enum RiskLevel: Sendable, Equatable {
    case low
    case medium
    case high
}

/// Le regole sono dati, non codice: un solo scanner le interpreta.
public struct CleanupRule: Sendable, Equatable {
    public let root: String
    public let mode: ScanMode
    public let includeGlobs: [String]
    public let excludeGlobs: [String]
    public let minAge: TimeInterval?
    public let minSizeBytes: Int64?
    public let maxDepth: Int
    public let requiresProjectMarker: Bool

    public init(
        _ root: String,
        _ mode: ScanMode,
        include includeGlobs: [String],
        exclude excludeGlobs: [String],
        minAge: TimeInterval? = nil,
        minSizeBytes: Int64? = nil,
        maxDepth: Int = .max,
        requiresProjectMarker: Bool = false
    ) {
        self.root = root
        self.mode = mode
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.minAge = minAge
        self.minSizeBytes = minSizeBytes
        self.maxDepth = maxDepth
        self.requiresProjectMarker = requiresProjectMarker
    }
}
