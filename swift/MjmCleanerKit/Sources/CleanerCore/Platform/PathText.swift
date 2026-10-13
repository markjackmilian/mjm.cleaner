import Foundation

/// Operazioni testuali sui percorsi POSIX con la stessa semantica dei metodi .NET su Unix usati
/// dall'app C# (`Path.GetFileName`, `Path.GetDirectoryName`, `Path.Combine`, `TrimEnd('/')`,
/// `Path.GetFullPath`) e il confronto `OrdinalIgnoreCase`. Nessuna funzione tocca il filesystem.
public enum PathText {
    /// Come `Path.GetFileName`: il testo dopo l'ultimo "/", vuoto se il percorso termina con "/".
    public static func fileName(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// Come `Path.GetDirectoryName` su Unix: `nil` per "/" e per la stringa vuota, "/" per un
    /// figlio diretto della radice, altrimenti il testo prima dell'ultimo "/". Un percorso
    /// relativo senza "/" restituisce la stringa vuota.
    public static func parent(_ path: String) -> String? {
        if path.isEmpty || path == "/" { return nil }
        guard let slash = path.lastIndex(of: "/") else { return "" }
        if slash == path.startIndex { return "/" }
        return String(path[..<slash])
    }

    /// Come `Path.Combine` con due argomenti: un secondo argomento assoluto vince.
    public static func join(_ base: String, _ component: String) -> String {
        if component.hasPrefix("/") || base.isEmpty { return component }
        if component.isEmpty { return base }
        return base.hasSuffix("/") ? base + component : base + "/" + component
    }

    /// Come `TrimEnd('/')`: "///" diventa la stringa vuota, esattamente come in .NET.
    public static func trimmingTrailingSlashes(_ path: String) -> String {
        var result = Substring(path)
        while result.hasSuffix("/") { result = result.dropLast() }
        return String(result)
    }

    /// Normalizzazione testuale di un percorso assoluto, come `Path.GetFullPath` su Unix:
    /// separatori ripetuti ridotti, segmenti "." eliminati, ".." risolto sul segmento precedente
    /// SENZA seguire i collegamenti. Serve solo a riprodurre la `FullName` che .NET restituiva per
    /// la destinazione di un collegamento simbolico: non va mai usata per validare un percorso da
    /// eliminare (vedi `CanonicalPath`, che i segmenti "." e ".." li rifiuta).
    public static func normalize(_ absolutePath: String) -> String {
        var segments: [Substring] = []
        for segment in absolutePath.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".":
                continue
            case "..":
                if !segments.isEmpty { segments.removeLast() }
            default:
                segments.append(segment)
            }
        }
        return "/" + segments.joined(separator: "/")
    }

    /// Confronto ordinale senza distinzione fra maiuscole e minuscole (`OrdinalIgnoreCase`): APFS
    /// è case-insensitive nella configurazione predefinita, quindi "~/documents" e "~/Documents"
    /// sono la stessa cartella.
    public static func equalsIgnoringCase(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .literal]) == .orderedSame
    }

    /// `StartsWith(prefix, OrdinalIgnoreCase)`; come in .NET, il prefisso vuoto è sempre presente.
    public static func hasPrefixIgnoringCase(_ text: String, _ prefix: String) -> Bool {
        if prefix.isEmpty { return true }
        return text.range(of: prefix, options: [.anchored, .caseInsensitive, .literal]) != nil
    }

    /// Vero se `path` coincide con `ancestor` o vi è contenuto, rispettando il confine di
    /// segmento ("/Library/CachesExtra" non è sotto "/Library/Caches").
    public static func isSameOrUnder(_ path: String, _ ancestor: String) -> Bool {
        equalsIgnoringCase(path, ancestor) || hasPrefixIgnoringCase(path, ancestor + "/")
    }
}
