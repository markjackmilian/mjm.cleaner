import CleanerCore
import Foundation
import Synchronization

/// Raccoglie valori da callback `@Sendable` e da doppi chiamati fuori dal main actor.
final class Recorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}

/// Un segnale che si apre una volta sola, con un valore: chi attende prima dell'apertura resta
/// sospeso, chi arriva dopo riceve subito il valore. Sostituisce i `TaskCompletionSource` del C#.
final class Gate<Value: Sendable>: Sendable {
    private struct State {
        var value: Value?
        var waiters: [CheckedContinuation<Value, Never>] = []
    }

    private let state = Mutex(State())

    var isOpen: Bool {
        state.withLock { $0.value != nil }
    }

    func open(_ value: Value) {
        let waiters = state.withLock { state -> [CheckedContinuation<Value, Never>] in
            guard state.value == nil else { return [] }
            state.value = value
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters {
            waiter.resume(returning: value)
        }
    }

    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Value? in
                if let value = state.value { return value }
                state.waiters.append(continuation)
                return nil
            }
            if let ready {
                continuation.resume(returning: ready)
            }
        }
    }
}

extension Gate where Value == Void {
    func open() {
        open(())
    }
}

/// Un errore qualunque lanciato da un doppio, come `new IOException("…")` nei test C#.
struct UnexpectedTestError: Error, CustomStringConvertible {
    let description: String
}

struct FixedWallClock: WallClock {
    let now: Date
}

/// Cartella temporanea reale: la composizione vera scrive `history.db` e i log su disco.
struct TemporaryDirectory {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        path = PathText.join(PathText.trimmingTrailingSlashes(base), "mjm-cleaner-features-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// Un `CleanReport` vuoto o con i valori indicati.
func makeReport(
    bytesFreed: Int64 = 0,
    itemsDeleted: Int = 0,
    itemsFailed: Int = 0,
    duration: Duration = .zero,
    categories: [CategoryCleanResult] = [],
    errors: [ScanError] = [],
    deletedPaths: [String] = []
) -> CleanReport {
    CleanReport(
        startedAt: Date(timeIntervalSince1970: 1_790_000_000),
        duration: duration,
        bytesFreed: bytesFreed,
        itemsDeleted: itemsDeleted,
        itemsFailed: itemsFailed,
        categories: categories,
        errors: errors,
        deletedPaths: deletedPaths)
}

func makeCategory(_ id: String, name: String? = nil, parent: String? = nil, risk: RiskLevel = .low) -> CleanupCategory {
    CleanupCategory(
        id: id, displayName: name ?? id, description: "descrizione", risk: risk,
        selectedByDefault: false, parentId: parent, rules: [])
}

func makeItem(_ path: String, size: Int64 = 100, root: String = "/Users/tester/Library/Caches") -> ScanItem {
    ScanItem(path: path, sizeBytes: size, isDirectory: false, declaredRoot: root)
}
