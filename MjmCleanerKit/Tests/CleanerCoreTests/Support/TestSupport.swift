import CleanerCore
import Foundation
import Synchronization

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

/// Raccoglie valori da callback `@Sendable` (avanzamento, diario): l'equivalente della lista
/// protetta da `lock` nei test C#.
final class Recorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}
