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
    /// Le cartelle escluse nelle Impostazioni, già espanse: mai attraversate né proposte, e nemmeno
    /// una cartella che ne contiene una (spec `2026-10-19-large-files-exclusions-design.md`).
    public let excludedPaths: [String]
    /// Rimuove le cartelle genitore diventate vuote dopo l'eliminazione di una voce selezionata.
    public let pruneEmptyDirectories: Bool

    public init(
        _ root: String,
        _ mode: ScanMode,
        include includeGlobs: [String],
        exclude excludeGlobs: [String],
        minAge: TimeInterval? = nil,
        minSizeBytes: Int64? = nil,
        maxDepth: Int = .max,
        requiresProjectMarker: Bool = false,
        excludedPaths: [String] = [],
        pruneEmptyDirectories: Bool = false
    ) {
        self.root = root
        self.mode = mode
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.minAge = minAge
        self.minSizeBytes = minSizeBytes
        self.maxDepth = maxDepth
        self.requiresProjectMarker = requiresProjectMarker
        self.excludedPaths = excludedPaths
        self.pruneEmptyDirectories = pruneEmptyDirectories
    }

    /// La stessa regola con le cartelle escluse nelle Impostazioni.
    public func excluding(_ excludedPaths: [String]) -> CleanupRule {
        CleanupRule(
            root, mode, include: includeGlobs, exclude: excludeGlobs, minAge: minAge, minSizeBytes: minSizeBytes,
            maxDepth: maxDepth, requiresProjectMarker: requiresProjectMarker, excludedPaths: excludedPaths,
            pruneEmptyDirectories: pruneEmptyDirectories)
    }

    /// La stessa regola senza la soglia minima di età.
    public func withoutMinimumAge() -> CleanupRule {
        CleanupRule(
            root, mode, include: includeGlobs, exclude: excludeGlobs, minAge: nil, minSizeBytes: minSizeBytes,
            maxDepth: maxDepth, requiresProjectMarker: requiresProjectMarker, excludedPaths: excludedPaths,
            pruneEmptyDirectories: pruneEmptyDirectories)
    }

    /// Attiva la rimozione delle cartelle genitore diventate vuote dopo l'eliminazione.
    public func pruningEmptyDirectories() -> CleanupRule {
        CleanupRule(
            root, mode, include: includeGlobs, exclude: excludeGlobs, minAge: minAge, minSizeBytes: minSizeBytes,
            maxDepth: maxDepth, requiresProjectMarker: requiresProjectMarker, excludedPaths: excludedPaths,
            pruneEmptyDirectories: true)
    }
}
