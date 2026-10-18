/// Valore JSON letto da `XcodeJsonReader`. Gli oggetti conservano l'ordine e le ripetizioni delle
/// proprietà come `JsonDocument`: l'ordine dei gruppi di dispositivi e delle immagini runtime
/// decide quale duplicato si considera per primo e l'ordine delle righe mostrate.
/// `JSONSerialization` restituirebbe un dizionario senza ordine.
enum XcodeJsonValue: Sendable {
    case object([XcodeJsonMember])
    case array([XcodeJsonValue])
    case string(String)
    /// Il numero com'è scritto nel documento: l'interpretazione spetta a chi legge.
    case number(String)
    case bool(Bool)
    case null

    /// `JsonElement.TryGetProperty`: confronto ordinale del nome; con nomi ripetuti vince l'ultimo
    /// (misurato su .NET 10). `nil` se il valore non è un oggetto o la proprietà manca.
    func property(_ name: String) -> XcodeJsonValue? {
        guard case .object(let members) = self else { return nil }
        return members.last { XcodeText.same($0.name, name) }?.value
    }

    /// Il testo di una proprietà stringa, altrimenti `nil` (helper `String` del C#).
    func string(_ name: String) -> String? {
        guard case .string(let text)? = property(name) else { return nil }
        return text
    }

    /// Un booleano, altrimenti `nil` (helper `Bool` del C#).
    func bool(_ name: String) -> Bool? {
        guard case .bool(let value)? = property(name) else { return nil }
        return value
    }

    /// Helper `OptionalInt64` del C#: proprietà assente → (`nil`, false); numero intero
    /// rappresentabile in 64 bit → (valore, false); qualunque altra cosa → (`nil`, true). Come
    /// `TryGetInt64`, "100.0" e "1e2" non sono interi.
    func optionalInt64(_ name: String) -> (value: Int64?, malformed: Bool) {
        guard let value = property(name) else { return (nil, false) }
        guard case .number(let literal) = value, let number = Int64(literal) else { return (nil, true) }
        return (number, false)
    }
}

struct XcodeJsonMember: Sendable {
    let name: String
    let value: XcodeJsonValue
}

/// JSON non valido: l'equivalente di `JsonException`. Il testo differisce da quello inglese di
/// .NET, come per gli errori di sistema (spec §5.3).
struct XcodeJsonSyntaxError: Error, Equatable, Sendable, CustomStringConvertible {
    let offset: Int

    var description: String {
        String(localized: "JSON non valido al byte \(offset)", bundle: .module)
    }
}

/// Lettore JSON rigoroso come `JsonDocument.Parse` con le opzioni predefinite: niente commenti,
/// niente virgole finali, niente zeri iniziali, profondità massima 64, un solo valore per
/// documento. Una sequenza `\u` con un surrogato isolato rende il documento non valido (.NET lo
/// accetta e lancia solo leggendo la stringa).
struct XcodeJsonReader {
    private static let maxDepth = 64

    private let bytes: [UInt8]
    private var position = 0

    private init(_ text: String) {
        bytes = Array(text.utf8)
    }

    static func parse(_ text: String) throws -> XcodeJsonValue {
        var reader = XcodeJsonReader(text)
        reader.skipWhiteSpace()
        let value = try reader.readValue(depth: 0)
        reader.skipWhiteSpace()
        guard reader.peek() == nil else { throw reader.failure() }
        return value
    }

    // MARK: - Valori

    private mutating func readValue(depth: Int) throws -> XcodeJsonValue {
        switch peek() {
        case UInt8(ascii: "{"):
            return try readObject(depth: depth + 1)
        case UInt8(ascii: "["):
            return try readArray(depth: depth + 1)
        case UInt8(ascii: "\""):
            return .string(try readString())
        case UInt8(ascii: "t"):
            try expect("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try expect("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try expect("null")
            return .null
        default:
            return .number(try readNumber())
        }
    }

    private mutating func readObject(depth: Int) throws -> XcodeJsonValue {
        guard depth <= Self.maxDepth else { throw failure() }
        position += 1
        var members: [XcodeJsonMember] = []
        skipWhiteSpace()
        if peek() == UInt8(ascii: "}") {
            position += 1
            return .object(members)
        }
        while true {
            skipWhiteSpace()
            guard peek() == UInt8(ascii: "\"") else { throw failure() }
            let name = try readString()
            skipWhiteSpace()
            guard peek() == UInt8(ascii: ":") else { throw failure() }
            position += 1
            skipWhiteSpace()
            members.append(XcodeJsonMember(name: name, value: try readValue(depth: depth)))
            skipWhiteSpace()
            switch peek() {
            case UInt8(ascii: ","):
                position += 1
            case UInt8(ascii: "}"):
                position += 1
                return .object(members)
            default:
                throw failure()
            }
        }
    }

    private mutating func readArray(depth: Int) throws -> XcodeJsonValue {
        guard depth <= Self.maxDepth else { throw failure() }
        position += 1
        var elements: [XcodeJsonValue] = []
        skipWhiteSpace()
        if peek() == UInt8(ascii: "]") {
            position += 1
            return .array(elements)
        }
        while true {
            skipWhiteSpace()
            elements.append(try readValue(depth: depth))
            skipWhiteSpace()
            switch peek() {
            case UInt8(ascii: ","):
                position += 1
            case UInt8(ascii: "]"):
                position += 1
                return .array(elements)
            default:
                throw failure()
            }
        }
    }

    private mutating func readString() throws -> String {
        position += 1
        var output: [UInt8] = []
        while true {
            guard let byte = peek() else { throw failure() }
            position += 1
            switch byte {
            case UInt8(ascii: "\""):
                return String(decoding: output, as: UTF8.self)
            case UInt8(ascii: "\\"):
                try readEscape(into: &output)
            case 0x00..<0x20:
                // Un carattere di controllo non escapato non è JSON valido.
                throw failure()
            default:
                // Il testo arriva da una String Swift: i byte non ASCII formano già UTF-8 valido.
                output.append(byte)
            }
        }
    }

    private mutating func readEscape(into output: inout [UInt8]) throws {
        guard let escape = peek() else { throw failure() }
        position += 1
        switch escape {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): output.append(escape)
        case UInt8(ascii: "b"): output.append(0x08)
        case UInt8(ascii: "f"): output.append(0x0C)
        case UInt8(ascii: "n"): output.append(0x0A)
        case UInt8(ascii: "r"): output.append(0x0D)
        case UInt8(ascii: "t"): output.append(0x09)
        case UInt8(ascii: "u"):
            let unit = try readHexUnit()
            let scalarValue: UInt32
            switch unit {
            case 0xD800...0xDBFF:
                guard peek() == UInt8(ascii: "\\") else { throw failure() }
                position += 1
                guard peek() == UInt8(ascii: "u") else { throw failure() }
                position += 1
                let low = try readHexUnit()
                guard (0xDC00...0xDFFF).contains(low) else { throw failure() }
                scalarValue = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
            case 0xDC00...0xDFFF:
                throw failure()
            default:
                scalarValue = unit
            }
            guard let scalar = Unicode.Scalar(scalarValue) else { throw failure() }
            output.append(contentsOf: Array(String(Character(scalar)).utf8))
        default:
            throw failure()
        }
    }

    private mutating func readHexUnit() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = peek() else { throw failure() }
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
            default: throw failure()
            }
            value = value * 16 + digit
            position += 1
        }
        return value
    }

    /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`, restituito com'è scritto.
    private mutating func readNumber() throws -> String {
        let start = position
        if peek() == UInt8(ascii: "-") { position += 1 }
        if peek() == UInt8(ascii: "0") {
            position += 1
        } else {
            guard isDigit(peek()) else { throw failure() }
            skipDigits()
        }
        if peek() == UInt8(ascii: ".") {
            position += 1
            guard isDigit(peek()) else { throw failure() }
            skipDigits()
        }
        if peek() == UInt8(ascii: "e") || peek() == UInt8(ascii: "E") {
            position += 1
            if peek() == UInt8(ascii: "+") || peek() == UInt8(ascii: "-") { position += 1 }
            guard isDigit(peek()) else { throw failure() }
            skipDigits()
        }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    // MARK: - Supporto

    private func peek() -> UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    private func isDigit(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private mutating func skipDigits() {
        while isDigit(peek()) { position += 1 }
    }

    /// Spazi ammessi fra i token JSON: spazio, tabulazione, a capo, ritorno carrello.
    private mutating func skipWhiteSpace() {
        while let byte = peek(), byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            position += 1
        }
    }

    private mutating func expect(_ literal: String) throws {
        for expected in literal.utf8 {
            guard peek() == expected else { throw failure() }
            position += 1
        }
    }

    private func failure() -> XcodeJsonSyntaxError {
        XcodeJsonSyntaxError(offset: position)
    }
}
