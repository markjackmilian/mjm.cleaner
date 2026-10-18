/// Un percorso è "canonico" quando è assoluto, non contiene il carattere NUL, e non richiede
/// alcuna risoluzione: nessun segmento "." o "..", nessun separatore ridondante.
///
/// Condiviso da `DenyList` e `PathGuard`, che devono rifiutare i percorsi non canonici con la
/// stessa identica definizione: un percorso che l'una accetta e l'altro respinge (o viceversa)
/// apre un varco fra le due linee di difesa. Non è usato da `PathExpander`, che riceve percorsi
/// con "~" e "$TMPDIR" — non percorsi già assoluti da validare.
enum CanonicalPath {
    private static let slash = UInt8(ascii: "/")
    private static let dot = UInt8(ascii: ".")

    /// La forma normalizzata (senza "/" finali; "/" per la radice), oppure `nil` se il percorso
    /// non è canonico.
    static func canonical(_ path: String?) -> String? {
        guard let path else { return nil }
        let bytes = Array(path.utf8)

        // Assoluto e senza NUL. Il primo byte "/" esclude anche la stringa vuota e quella di soli spazi.
        guard bytes.first == slash, !bytes.contains(0) else { return nil }

        // Controlli sui byte UTF-8, non sui caratteri Swift: "/" e "." sono ASCII e non compaiono mai
        // dentro una sequenza multibyte, quindi l'esito coincide con il confronto per unità UTF-16
        // del C#. Sui caratteri, uno scalare "Prepend" (U+0600) o un segno combinante si fonderebbe
        // con "/" in un solo grafema e nasconderebbe un "/../" che il kernel risolve comunque.
        if contains(bytes, [slash, slash])
            || contains(bytes, [slash, dot, slash])
            || contains(bytes, [slash, dot, dot, slash])
            || bytes.suffix(2).elementsEqual([slash, dot])
            || bytes.suffix(3).elementsEqual([slash, dot, dot]) {
            return nil
        }

        var end = bytes.count
        while end > 0, bytes[end - 1] == slash { end -= 1 }
        return end == 0 ? "/" : String(decoding: bytes[..<end], as: UTF8.self)
    }

    private static func contains(_ bytes: [UInt8], _ pattern: [UInt8]) -> Bool {
        guard bytes.count >= pattern.count else { return false }
        for start in 0...(bytes.count - pattern.count)
        where bytes[start..<(start + pattern.count)].elementsEqual(pattern) {
            return true
        }
        return false
    }
}
