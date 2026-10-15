import CleanerCore
import Foundation
import Synchronization
import Testing

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
///
/// Ogni attesa ha un limite: il tratto `.timeLimit` di Swift Testing non interrompe un test sospeso
/// su una continuation, così un segnale che una regressione non apre bloccherebbe la suite invece
/// di farla fallire.
final class Gate<Value: Sendable>: Sendable {
    private struct State {
        var value: Value?
        var nextWaiter = 0
        var waiters: [Int: CheckedContinuation<Value?, Never>] = [:]
    }

    private let state = Mutex(State())

    func open(_ value: Value) {
        let waiters = state.withLock { state -> [CheckedContinuation<Value?, Never>] in
            guard state.value == nil else { return [] }
            state.value = value
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in waiters {
            waiter.resume(returning: value)
        }
    }

    /// Il valore, atteso al massimo `limit`: allo scadere `nil`, e l'attesa viene tolta dal segnale.
    func wait(within limit: Duration) async -> Value? {
        var timer: Task<Void, Never>?
        let value = await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
            let waiter = state.withLock { state -> Int? in
                guard state.value == nil else { return nil }
                defer { state.nextWaiter += 1 }
                state.waiters[state.nextWaiter] = continuation
                return state.nextWaiter
            }
            guard let waiter else {
                continuation.resume(returning: state.withLock { $0.value })
                return
            }
            // Il timer parte dopo la registrazione: non può scadere prima che l'attesa esista.
            timer = Task {
                do { try await Task.sleep(for: limit) } catch { return }
                self.state.withLock { $0.waiters.removeValue(forKey: waiter) }?.resume(returning: nil)
            }
        }
        timer?.cancel()
        return value
    }

    /// Il valore, atteso al massimo 5 secondi: allo scadere il test fallisce qui e l'attesa lancia,
    /// così chi attende non prosegue con uno stato che non c'è.
    func wait(sourceLocation: SourceLocation = #_sourceLocation) async throws -> Value {
        try #require(
            await wait(within: .seconds(5)), "Il segnale non si è aperto entro 5 secondi", sourceLocation: sourceLocation)
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
