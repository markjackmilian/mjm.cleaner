/// Operazioni testuali sui percorsi POSIX con la stessa semantica dei metodi .NET su Unix usati
/// dall'app C# (`Path.GetFileName`, `Path.GetDirectoryName`, `Path.Combine`, `TrimEnd('/')`,
/// `Path.GetFullPath`) e il confronto `OrdinalIgnoreCase`. Nessuna funzione tocca il filesystem.
public enum PathText {
    private static let slash = UInt8(ascii: "/")
    private static let dot = UInt8(ascii: ".")

    /// Come `Path.GetFileName`: il testo dopo l'ultimo "/", vuoto se il percorso termina con "/".
    /// Si cerca il byte "/" e non il carattere Swift: un segno combinante dopo "/" formerebbe con
    /// esso un solo grafema e lo nasconderebbe.
    public static func fileName(_ path: String) -> String {
        let bytes = path.utf8
        guard let separator = bytes.lastIndex(of: slash) else { return path }
        return String(decoding: bytes[bytes.index(after: separator)...], as: UTF8.self)
    }

    /// Come `Path.GetDirectoryName` su Unix (`GetDirectoryNameOffset` più la normalizzazione dei
    /// separatori di .NET): `nil` per la stringa vuota e per la sola radice "/", "/" per un figlio
    /// diretto della radice, altrimenti il testo prima dell'ultimo "/", senza i separatori finali e
    /// con i separatori ripetuti ridotti a uno ("/a//b" dà "/a"). Un percorso relativo senza "/"
    /// restituisce la stringa vuota.
    public static func parent(_ path: String) -> String? {
        let slash = UInt16(UInt8(ascii: "/"))
        let units = Array(path.utf16)
        let rootLength = units.first == slash ? 1 : 0
        if units.count <= rootLength { return nil }

        var end = units.count
        while end > rootLength {
            end -= 1
            if units[end] == slash { break }
        }
        while end > rootLength, units[end - 1] == slash {
            end -= 1
        }

        var collapsed: [UInt16] = []
        collapsed.reserveCapacity(end)
        for unit in units[..<end] {
            if unit == slash, collapsed.last == slash { continue }
            collapsed.append(unit)
        }
        return String(decoding: collapsed, as: UTF16.self)
    }

    /// Come `Path.Combine` con due argomenti: un secondo argomento assoluto vince.
    public static func join(_ base: String, _ component: String) -> String {
        if component.utf8.first == slash || base.isEmpty { return component }
        if component.isEmpty { return base }
        return base.utf8.last == slash ? base + component : base + "/" + component
    }

    /// Come `TrimEnd('/')`: "///" diventa la stringa vuota, esattamente come in .NET.
    public static func trimmingTrailingSlashes(_ path: String) -> String {
        let bytes = Array(path.utf8)
        var end = bytes.count
        while end > 0, bytes[end - 1] == slash { end -= 1 }
        return String(decoding: bytes[..<end], as: UTF8.self)
    }

    /// Normalizzazione testuale di un percorso assoluto, come `Path.GetFullPath` su Unix:
    /// separatori ripetuti ridotti, segmenti "." eliminati, ".." risolto sul segmento precedente
    /// SENZA seguire i collegamenti. Serve solo a riprodurre la `FullName` che .NET restituiva per
    /// la destinazione di un collegamento simbolico: non va mai usata per validare un percorso da
    /// eliminare (vedi `CanonicalPath`, che i segmenti "." e ".." li rifiuta). Diversamente da
    /// `Path.GetFullPath`, il "/" finale non viene conservato (`/a/` diventa `/a`): l'unico
    /// consumatore, la risoluzione del bersaglio di un collegamento passata a PathGuard, lo elimina
    /// comunque.
    public static func normalize(_ absolutePath: String) -> String {
        var segments: [ArraySlice<UInt8>] = []
        for segment in Array(absolutePath.utf8).split(separator: slash, omittingEmptySubsequences: true) {
            if segment.elementsEqual([dot]) { continue }
            if segment.elementsEqual([dot, dot]) {
                if !segments.isEmpty { segments.removeLast() }
                continue
            }
            segments.append(segment)
        }
        return "/" + segments.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "/")
    }

    /// Confronto senza distinzione fra maiuscole e minuscole con la semantica di `OrdinalIgnoreCase`:
    /// scalare per scalare, senza equivalenza canonica, e la lunghezza non cambia mai (vedi `fold`).
    /// APFS è case-insensitive nella configurazione predefinita, quindi "~/documents" e "~/Documents"
    /// sono la stessa cartella.
    public static func equalsIgnoringCase(_ lhs: String, _ rhs: String) -> Bool {
        var left = lhs.unicodeScalars.makeIterator()
        var right = rhs.unicodeScalars.makeIterator()
        while true {
            switch (left.next(), right.next()) {
            case (nil, nil):
                return true
            case let (leftScalar?, rightScalar?):
                if fold(leftScalar) != fold(rightScalar) { return false }
            default:
                return false
            }
        }
    }

    /// `StartsWith(prefix, OrdinalIgnoreCase)`; come in .NET, il prefisso vuoto è sempre presente.
    /// Un prefisso riconosciuto occupa in `text` lo stesso numero di scalari di `prefix`.
    public static func hasPrefixIgnoringCase(_ text: String, _ prefix: String) -> Bool {
        var textScalars = text.unicodeScalars.makeIterator()
        for prefixScalar in prefix.unicodeScalars {
            guard let textScalar = textScalars.next(), fold(textScalar) == fold(prefixScalar) else { return false }
        }
        return true
    }

    /// Il testo ripiegato per i confronti senza maiuscole: usato anche da `SimpleGlob`.
    static func folded(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.map(fold))
        return String(scalars)
    }

    /// Ripiegamento per i confronti senza maiuscole, con la semantica di `OrdinalIgnoreCase` di
    /// .NET 10: mappatura semplice alla maiuscola, scalare per scalare, lunghezza invariata. Swift
    /// espone solo le mappature complete, quindi si usa la maiuscola quando è un solo scalare,
    /// altrimenti la titlecase quando è un solo scalare (recupera le lettere greche con
    /// ypogegrammeni, che .NET equipara), altrimenti lo scalare resta com'è: "ß" resta "ß", le
    /// legature restano tali. Restano invariati anche i casi che .NET distingue: "ı" (U+0131) e "ſ"
    /// (U+017F), e il blocco U+16EA0–U+16EDF, assente dai dati Unicode di .NET 10. Principio: non
    /// equiparare mai due scalari che .NET distingue, perché renderebbe più permissivo il
    /// contenimento del PathGuard; perdere un'equivalenza di .NET fa solo negare di più.
    private static func fold(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        if scalar.isASCII {
            let value = scalar.value
            return (97...122).contains(value) ? Unicode.Scalar(UInt8(value - 32)) : scalar
        }
        let value = scalar.value
        if value == 0x0131 || value == 0x017F || (0x16EA0...0x16EDF).contains(value) {
            return scalar
        }
        let properties = scalar.properties
        let upper = properties.uppercaseMapping.unicodeScalars
        if upper.count == 1, let mapped = upper.first { return mapped }
        let title = properties.titlecaseMapping.unicodeScalars
        if title.count == 1, let mapped = title.first { return mapped }
        return scalar
    }

    /// Vero se `path` coincide con `ancestor` o vi è contenuto, rispettando il confine di
    /// segmento ("/Library/CachesExtra" non è sotto "/Library/Caches").
    public static func isSameOrUnder(_ path: String, _ ancestor: String) -> Bool {
        equalsIgnoringCase(path, ancestor) || hasPrefixIgnoringCase(path, ancestor + "/")
    }
}
