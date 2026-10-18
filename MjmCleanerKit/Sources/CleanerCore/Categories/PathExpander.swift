import Foundation

/// Traduce i percorsi delle regole in percorsi assoluti.
public struct PathExpander: Sendable {
    private let home: String
    private let temp: String

    public init(homeDirectory: String?, tempDirectory: String?) throws {
        home = try Self.normalize(homeDirectory)
        temp = try Self.normalize(tempDirectory)
    }

    public func expand(_ path: String) -> String {
        let expanded: String
        if path == "~" {
            expanded = home
        } else if path == "$TMPDIR" {
            expanded = temp
        } else if path.utf8.starts(with: [UInt8(ascii: "~"), UInt8(ascii: "/")]) {
            // Si confrontano i byte, non i caratteri Swift: un segno combinante dopo "/" lo
            // fonderebbe in un solo grafema.
            expanded = home + String(decoding: path.utf8.dropFirst(), as: UTF8.self)
        } else {
            expanded = path
        }
        return expanded.utf8.count > 1 ? PathText.trimmingTrailingSlashes(expanded) : expanded
    }

    /// Home reale e `$TMPDIR` dell'utente: fuori dalla sandbox `NSTemporaryDirectory()` è la
    /// cartella per-utente sotto /var/folders, come `Path.GetTempPath()` in .NET.
    public static func forCurrentUser() throws -> PathExpander {
        try PathExpander(homeDirectory: NSHomeDirectory(), tempDirectory: NSTemporaryDirectory())
    }

    // Validato DOPO la rimozione dei "/" finali, non prima: lo stesso difetto misurato in
    // DenyList. Un valore come "//" o "/" supera un controllo sul solo valore grezzo, ma ridotto
    // diventa "": expand("~") o expand("$TMPDIR") restituirebbero la stringa vuota.
    private static func normalize(_ directory: String?) throws -> String {
        guard let directory, directory.utf8.first == UInt8(ascii: "/") else {
            throw InvalidConfiguration("Il percorso deve essere assoluto.")
        }
        let normalized = PathText.trimmingTrailingSlashes(directory)
        guard !normalized.isEmpty else {
            throw InvalidConfiguration("Il percorso deve restare un percorso assoluto non degenere dopo la normalizzazione.")
        }
        return normalized
    }
}
