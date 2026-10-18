import Foundation

/// Converte le dimensioni testuali stampate dalla CLI ("195MB", "1.131kB", "76.74MB (2%)").
/// Docker usa unità DECIMALI (go-units HumanSize: 1 kB = 1000 B), non binarie: interpretarle come
/// potenze di 1024 gonfierebbe del 7% ogni dimensione in GB mostrata all'utente.
public enum DockerSize {
    /// `nil` per "N/A", vuoto o testo non riconosciuto: una dimensione ignota non è zero.
    public static func parse(_ text: String?) -> Int64? {
        guard let text, !DockerText.isBlank(text) else { return nil }

        // Porting di `^\s*(?<value>\d+(?:\.\d+)?)\s*(?<unit>[kKMGTP]?B)\b` di .NET:
        // - `[0-9]` al posto di `\d`: .NET accetta anche le cifre non ASCII, ma poi
        //   `decimal.TryParse` le rifiuta, quindi l'esito è comunque nullo;
        // - `\b` dopo una "B" diventa «il carattere seguente non è una lettera di parola di .NET»:
        //   lettere (L), segni Mn, cifre Nd, connettori Pc, U+200C e U+200D, solo nel piano base
        //   (.NET confronta unità UTF-16 e un surrogato non è mai lettera). Il `\b` di Swift segue
        //   regole diverse, anche con `.wordBoundaryKind(.simple)`.
        let pattern = /^\s*(?<value>[0-9]+(?:\.[0-9]+)?)\s*(?<unit>[kKMGTP]?B)(?![[\p{L}\p{Mn}\p{Nd}\p{Pc}\u{200C}\u{200D}]&&[\x{0}-\x{FFFF}]])/
            .matchingSemantics(.unicodeScalar)

        guard let match = text.firstMatch(of: pattern),
              let value = Decimal(string: String(match.output.value), locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        var product = value * Decimal(multiplier(String(match.output.unit)))
        var rounded = Decimal()
        // `Math.Round(decimal)` di .NET arrotonda al pari (MidpointRounding.ToEven).
        NSDecimalRound(&rounded, &product, 0, .bankers)
        // Oltre Int64 il C# lanciava OverflowException dal cast: qui la dimensione resta ignota.
        return Int64(rounded.description)
    }

    /// La tabella `B`/`kB`/`MB`/`GB`/`TB`/`PB` del C#, senza distinzione fra maiuscole e minuscole.
    private static func multiplier(_ unit: String) -> Int64 {
        switch unit.utf8.first {
        case UInt8(ascii: "k"), UInt8(ascii: "K"): 1_000
        case UInt8(ascii: "M"): 1_000_000
        case UInt8(ascii: "G"): 1_000_000_000
        case UInt8(ascii: "T"): 1_000_000_000_000
        case UInt8(ascii: "P"): 1_000_000_000_000_000
        default: 1
        }
    }
}
