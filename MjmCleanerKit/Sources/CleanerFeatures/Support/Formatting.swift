import Foundation

/// Numeri, dimensioni e date dell'interfaccia, come `ViewModelBase.FormatBytes`, il formato `N0` e
/// `d MMM yyyy, HH:mm` del C# con la cultura it-IT. Scritti a mano e non con le tabelle ICU del
/// sistema: lo stesso testo su ogni macchina e nei test (spec §6.5; `ByteCountFormatter` lavora in
/// base 1000 e mostrerebbe numeri diversi).
public enum Formatting {
    /// Abbreviazioni dei mesi di it-IT, come le scrive .NET (misurato: «6 set 2026, 09:05»).
    private static let months = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]

    /// `FormatBytes`: base 1024, unità B/KB/MB/GB/TB, al massimo un decimale con la virgola.
    /// L'arrotondamento è lontano dallo zero come il formato `0.#` di .NET: 1280 B → «1,3 KB».
    public static func bytes(_ bytes: Int64) -> String {
        var value = Double(bytes)
        var scaledUnit: String?
        for next in ["KB", "MB", "GB", "TB"] where value >= 1024 {
            value /= 1024
            scaledUnit = next
        }

        guard let unit = scaledUnit else { return "\(bytes) B" }

        // Il valore è al massimo 8 388 608 (Int64.max in TB): i decimi stanno in un Int64.
        let tenths = Int64((value * 10).rounded(.toNearestOrAwayFromZero))
        let whole = tenths / 10
        let fraction = tenths % 10
        return fraction == 0 ? "\(whole) \(unit)" : "\(whole),\(fraction) \(unit)"
    }

    /// Il formato `N0` di it-IT: punto come separatore delle migliaia, nessun decimale.
    public static func integer<Number: BinaryInteger>(_ value: Number) -> String {
        let digits = Array(String(value.magnitude))
        var grouped = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0 && (digits.count - offset) % 3 == 0 {
                grouped.append(".")
            }
            grouped.append(digit)
        }
        return value < 0 ? "-" + grouped : grouped
    }

    /// Concordanza minima singolare/plurale: evita «1 elementi» quando `count` è 1.
    public static func plural(_ count: Int, _ singular: String, _ plural: String) -> String {
        count == 1 ? singular : plural
    }

    /// I secondi interi di una durata, come `{0:0}` su `TimeSpan.TotalSeconds` (2,5 → «3»).
    public static func seconds(_ duration: Duration) -> String {
        let parts = duration.components
        let total = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return String(Int64(total.rounded(.toNearestOrAwayFromZero)))
    }

    /// Data dello storico in ora locale, `d MMM yyyy, HH:mm` con i mesi di it-IT: i timestamp
    /// sono salvati in UTC e resi in ora locale, altrimenti il cambio d'ora riordinerebbe lo storico.
    public static func historyDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let monthIndex = (parts.month ?? 1) - 1
        let month = months.indices.contains(monthIndex) ? months[monthIndex] : ""
        return String(
            format: "%ld %@ %ld, %02ld:%02ld",
            parts.day ?? 0, month, parts.year ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }
}
