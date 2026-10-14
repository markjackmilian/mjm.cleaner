import Darwin

/// Le operazioni sul testo che il C# di Xcode faceva con `string` e `StringComparison`, con la
/// stessa semantica: confronti ordinali sui byte UTF-8 (una `String` Swift confronterebbe per
/// equivalenza canonica), spazi come `char.IsWhiteSpace` e `\s` di .NET, righe divise solo su
/// "\n" (in Swift "\r\n" è un solo `Character` e non verrebbe diviso).
enum XcodeText {
    /// `string.Equals(a, b, StringComparison.Ordinal)`: due `nil` sono uguali.
    static func same(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (left?, right?): left.utf8.elementsEqual(right.utf8)
        default: false
        }
    }

    /// Chiave per insiemi e dizionari con `StringComparer.Ordinal`.
    static func ordinalKey(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    /// Chiave per insiemi e dizionari con `StringComparer.OrdinalIgnoreCase`.
    static func caseInsensitiveKey(_ text: String) -> [UInt8] {
        Array(PathText.folded(text).utf8)
    }

    /// `Distinct(StringComparer.Ordinal)`: conserva la prima occorrenza e l'ordine.
    static func distinct(_ texts: [String]) -> [String] {
        var seen = Set<[UInt8]>()
        return texts.filter { seen.insert(ordinalKey($0)).inserted }
    }

    /// `text.StartsWith(prefix, StringComparison.Ordinal)`.
    static func hasOrdinalPrefix(_ text: String, _ prefix: String) -> Bool {
        text.utf8.starts(with: prefix.utf8)
    }

    /// `text.Contains(fragment, StringComparison.OrdinalIgnoreCase)`: ricerca sui testi ripiegati
    /// da `PathText.folded`, che non cambia mai il numero di scalari.
    static func containsIgnoringCase(_ text: String, _ fragment: String) -> Bool {
        let haystack = Array(PathText.folded(text).unicodeScalars)
        let needle = Array(PathText.folded(fragment).unicodeScalars)
        guard needle.count <= haystack.count else { return false }
        guard !needle.isEmpty else { return true }
        for start in 0...(haystack.count - needle.count)
        where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return true
        }
        return false
    }

    /// Gli spazi di `char.IsWhiteSpace` e di `\s` nelle regex .NET: U+0009–U+000D, U+0085 e le
    /// categorie Unicode Zs, Zl, Zp.
    static func isWhiteSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x85:
            return true
        default:
            switch scalar.properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
            default: return false
            }
        }
    }

    /// `string.Trim()`.
    static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !isWhiteSpace($0) }),
              let last = scalars.lastIndex(where: { !isWhiteSpace($0) }) else { return "" }
        return String(scalars[first...last])
    }

    /// `string.IsNullOrWhiteSpace`.
    static func isNullOrWhiteSpace(_ text: String?) -> Bool {
        guard let text else { return true }
        return text.unicodeScalars.allSatisfy(isWhiteSpace)
    }

    /// `text.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)`.
    static func lines(_ text: String) -> [String] {
        text.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { trimmed(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// `Exception.Message` per gli errori che arrivano fino all'utente.
    static func message(_ error: any Error) -> String {
        switch error {
        case let error as FileSystemError:
            return error.message
        case let error as ProcessLaunchError:
            return String(cString: strerror(error.code))
        case is CancellationError:
            return String(localized: "operazione annullata", bundle: .module)
        default:
            return String(describing: error)
        }
    }
}

/// Riconoscimento degli UUID come `Guid` in .NET, restituiti nella forma canonica "D" minuscola.
enum XcodeUuid {
    private static let hyphenOffsets: Set<Int> = [8, 13, 18, 23]

    /// `Guid.TryParseExact(text, "D", …)`: 8-4-4-4-12 cifre esadecimali, spazi esterni ignorati.
    /// Più rigoroso di .NET, che dentro i gruppi accetta anche "+" e "0x" (misurato su .NET 10:
    /// "+1111111-…" diventa "01111111-…").
    static func canonicalExact(_ text: String) -> String? {
        exactD(Array(XcodeText.trimmed(text).utf8))
    }

    /// `Guid.TryParse`: forme "D", "N" (32 cifre), "B" ({…}) e "P" ((…)). La forma "X"
    /// ({0x…,{0x…}}) non è riconosciuta: la chiave resta testo e non corrisponde a nessun UUID.
    static func canonical(_ text: String) -> String? {
        let bytes = Array(XcodeText.trimmed(text).utf8)
        switch bytes.count {
        case 36:
            return exactD(bytes)
        case 32:
            let digits = bytes.compactMap(lowercaseHexDigit)
            return digits.count == 32 ? format(digits) : nil
        case 38:
            guard let open = bytes.first, let close = bytes.last,
                  (open == UInt8(ascii: "{") && close == UInt8(ascii: "}"))
                    || (open == UInt8(ascii: "(") && close == UInt8(ascii: ")")) else { return nil }
            return exactD(Array(bytes.dropFirst().dropLast()))
        default:
            return nil
        }
    }

    /// Lavora sui byte UTF-8: ogni carattere ammesso è ASCII, quindi un carattere non ASCII
    /// fallisce comunque il controllo di cifra o di lunghezza.
    private static func exactD(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 36 else { return nil }
        var digits: [UInt8] = []
        for (offset, byte) in bytes.enumerated() {
            if hyphenOffsets.contains(offset) {
                guard byte == UInt8(ascii: "-") else { return nil }
            } else {
                guard let digit = lowercaseHexDigit(byte) else { return nil }
                digits.append(digit)
            }
        }
        return format(digits)
    }

    private static func lowercaseHexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "a")...UInt8(ascii: "f"): byte
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte + 32
        default: nil
        }
    }

    /// 32 cifre esadecimali minuscole → "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx".
    private static func format(_ digits: [UInt8]) -> String {
        var result: [UInt8] = []
        for (offset, digit) in digits.enumerated() {
            if offset == 8 || offset == 12 || offset == 16 || offset == 20 { result.append(UInt8(ascii: "-")) }
            result.append(digit)
        }
        return String(decoding: result, as: UTF8.self)
    }
}
