import Foundation

/// Un percorso è "canonico" quando è assoluto, non contiene il carattere NUL, e non richiede
/// alcuna risoluzione: nessun segmento "." o "..", nessun separatore ridondante.
///
/// Condiviso da `DenyList` e `PathGuard`, che devono rifiutare i percorsi non canonici con la
/// stessa identica definizione: un percorso che l'una accetta e l'altro respinge (o viceversa)
/// apre un varco fra le due linee di difesa. Non è usato da `PathExpander`, che riceve percorsi
/// con "~" e "$TMPDIR" — non percorsi già assoluti da validare.
enum CanonicalPath {
    /// La forma normalizzata (senza "/" finali; "/" per la radice), oppure `nil` se il percorso
    /// non è canonico.
    static func canonical(_ path: String?) -> String? {
        guard let path,
              !path.allSatisfy(\.isWhitespace),
              path.hasPrefix("/"),
              !path.contains("\0") else {
            return nil
        }

        if path.contains("//")
            || path.contains("/./")
            || path.contains("/../")
            || path.hasSuffix("/.")
            || path.hasSuffix("/..") {
            return nil
        }

        let trimmed = PathText.trimmingTrailingSlashes(path)
        return trimmed.isEmpty ? "/" : trimmed
    }
}
