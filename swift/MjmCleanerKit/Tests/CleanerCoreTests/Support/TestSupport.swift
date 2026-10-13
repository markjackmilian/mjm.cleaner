import CleanerCore
import Foundation

/// Porting di `TestTimeProvider.cs`.
struct FixedWallClock: WallClock {
    let now: Date
}

/// `new DateTimeOffset(year, month, day, hour, minute, second, TimeSpan.Zero)`.
func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    return calendar.date(from: components) ?? .distantPast
}

/// `TimeSpan.FromDays(count)`.
func days(_ count: Double) -> TimeInterval {
    count * 86_400
}

/// Annulla il task in cui viene chiamata. Equivale a un `CancellationTokenSource` annullato: usata
/// prima della chiamata sotto test (annullamento anticipato) o dentro un callback di avanzamento
/// (annullamento a metà, deterministico perché il callback gira nel task stesso).
func cancelCurrentTask() {
    withUnsafeCurrentTask { $0?.cancel() }
}
