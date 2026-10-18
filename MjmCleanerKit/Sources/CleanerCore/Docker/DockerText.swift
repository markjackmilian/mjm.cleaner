import Foundation

/// Operazioni sul testo di Docker (output della CLI, nomi, file dei progetti) con la semantica dei
/// metodi .NET che il C# usava: `Split`/`Trim` sui caratteri, confronti `Ordinal` e
/// `OrdinalIgnoreCase`, `ToLowerInvariant`, `File.ReadAllText`. Lavorano su scalari e byte UTF-8,
/// mai sui `Character` di Swift: un segno combinante o uno scalare «prepend» formerebbero con il
/// separatore un solo grafema e lo nasconderebbero (registro decisioni del piano 1, Task 4).
enum DockerText {
    /// `text.Split('\n', RemoveEmptyEntries | TrimEntries)`: divide solo su "\n" (un "\r\n" lascia
    /// "\r", che `Trim` toglie), toglie gli spazi Unicode ai lati e scarta le righe vuote.
    static func lines(_ text: String) -> [String] {
        text.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { trimmed(String(Substring($0))) }
            .filter { !$0.isEmpty }
    }

    /// `text.Split('\n')` senza opzioni: anche le righe vuote, anche l'ultima.
    static func rawLines(_ text: String) -> [Substring] {
        text.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { Substring($0) }
    }

    /// `string.Trim()`: toglie ai lati gli scalari con la proprietà White_Space, lo stesso insieme
    /// di `char.IsWhiteSpace` (verificato su tutti gli scalari del piano base).
    static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
              let last = scalars.lastIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        return String(scalars[first...last])
    }

    /// `string.Trim(character)`: toglie ai lati tutte le ripetizioni di un solo carattere.
    static func trimmed(_ text: String, _ character: Unicode.Scalar) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { $0 != character }),
              let last = scalars.lastIndex(where: { $0 != character }) else { return "" }
        return String(scalars[first...last])
    }

    /// `string.TrimStart(character)`.
    static func trimmedLeading(_ text: String, _ character: Unicode.Scalar) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { $0 != character }) else { return "" }
        return String(scalars[first...])
    }

    /// `string.TrimEnd(character)`.
    static func trimmedTrailing(_ text: String, _ character: Unicode.Scalar) -> String {
        let scalars = text.unicodeScalars
        guard let last = scalars.lastIndex(where: { $0 != character }) else { return "" }
        return String(scalars[...last])
    }

    /// `IsNullOrWhiteSpace`.
    static func isBlank(_ text: String?) -> Bool {
        text?.unicodeScalars.allSatisfy(\.properties.isWhitespace) ?? true
    }

    /// `Contains(needle, StringComparison.Ordinal)`, sui byte UTF-8: per testi validi l'esito
    /// coincide con il confronto per unità UTF-16 di .NET.
    static func contains(_ text: String, _ needle: String) -> Bool {
        var remainder = text.utf8[...]
        while true {
            if remainder.starts(with: needle.utf8) { return true }
            if remainder.isEmpty { return false }
            remainder = remainder.dropFirst()
        }
    }

    /// `Contains(needle, StringComparison.OrdinalIgnoreCase)`: lo stesso ripiegamento di `PathText`.
    static func containsIgnoringCase(_ text: String, _ needle: String) -> Bool {
        contains(PathText.folded(text), PathText.folded(needle))
    }

    /// `StartsWith(prefix, StringComparison.Ordinal)`.
    static func hasPrefix(_ text: String, _ prefix: String) -> Bool {
        text.utf8.starts(with: prefix.utf8)
    }

    /// `EndsWith(suffix, StringComparison.Ordinal)`.
    static func hasSuffix(_ text: String, _ suffix: String) -> Bool {
        text.utf8.reversed().starts(with: suffix.utf8.reversed())
    }

    /// `EndsWith(suffix, StringComparison.OrdinalIgnoreCase)`.
    static func hasSuffixIgnoringCase(_ text: String, _ suffix: String) -> Bool {
        hasSuffix(PathText.folded(text), PathText.folded(suffix))
    }

    /// `Distinct(StringComparer.Ordinal)`: conserva la prima occorrenza e l'ordine. La chiave sono i
    /// byte UTF-8, non `String`: l'equivalenza canonica di Swift unirebbe valori che .NET distingue.
    static func distinct(_ values: [String]) -> [String] {
        var seen = Set<[UInt8]>()
        return values.filter { seen.insert(Array($0.utf8)).inserted }
    }

    /// `Order(StringComparer.Ordinal)`: per unità UTF-16, come .NET.
    static func ordinalSorted(_ values: some Sequence<String>) -> [String] {
        values.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    }

    /// `ToLowerInvariant`: mappatura semplice scalare per scalare, lunghezza invariata. Coincide con
    /// .NET 10 su tutti gli scalari (1487 mappature, confronto esaustivo durante la stesura del
    /// piano 2): dove la minuscola completa è di più scalari (per esempio U+0130) lo scalare resta.
    static func lowercasedInvariant(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let lower = scalar.properties.lowercaseMapping.unicodeScalars
            if lower.count == 1, let mapped = lower.first {
                scalars.append(mapped)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// Il contenuto di un file come `File.ReadAllText`: UTF-8 salvo un BOM che indichi UTF-16 o
    /// UTF-32; il BOM non fa parte del testo. Le sequenze non valide diventano U+FFFD.
    static func decodeLikeReadAllText(_ data: Data) -> String {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return decodeUTF32(bytes.dropFirst(4), bigEndian: false)
        }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return decodeUTF32(bytes.dropFirst(4), bigEndian: true)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return decodeUTF16(bytes.dropFirst(2), bigEndian: false)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return decodeUTF16(bytes.dropFirst(2), bigEndian: true)
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: bytes.dropFirst(3), as: UTF8.self)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func decodeUTF16(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) -> String {
        var units: [UInt16] = []
        var iterator = bytes.makeIterator()
        while let first = iterator.next() {
            guard let second = iterator.next() else {
                // Byte dispari in fondo: .NET lo sostituisce con U+FFFD.
                units.append(0xFFFD)
                break
            }
            units.append(bigEndian ? UInt16(first) << 8 | UInt16(second) : UInt16(second) << 8 | UInt16(first))
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func decodeUTF32(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) -> String {
        var units: [UInt32] = []
        var group: [UInt8] = []
        for byte in bytes {
            group.append(byte)
            guard group.count == 4 else { continue }
            let ordered = bigEndian ? group : group.reversed()
            units.append(ordered.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            group.removeAll()
        }
        if !group.isEmpty { units.append(0xFFFD) }
        return String(decoding: units, as: UTF32.self)
    }

    /// Le posizioni in cui un'ancora `^` di .NET con `RegexOptions.Multiline` può corrispondere:
    /// l'inizio del testo e ogni scalare dopo un "\n". Le ancore di riga di Swift scattano anche
    /// dopo "\r", "\u{B}", "\u{C}", U+0085, U+2028 e U+2029.
    static func lineStarts(_ text: String) -> [String.Index] {
        var starts = [text.startIndex]
        var index = text.unicodeScalars.startIndex
        for scalar in text.unicodeScalars {
            index = text.unicodeScalars.index(after: index)
            if scalar == "\n" { starts.append(index) }
        }
        return starts
    }
}
