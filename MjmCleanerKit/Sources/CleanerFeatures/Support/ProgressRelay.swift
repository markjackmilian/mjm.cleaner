/// Porta sul main actor, nell'ordine in cui arriva, l'avanzamento che il Core segnala dai propri
/// thread (spec §4.2: `IProgress<T>` → callback `@Sendable` consumato dal modello sul `MainActor`).
/// Un `Task { @MainActor in … }` per ogni valore non garantirebbe l'ordine: qui un solo
/// consumatore legge un `AsyncStream`.
@MainActor
final class ProgressRelay<Value: Sendable> {
    private let continuation: AsyncStream<Value>.Continuation
    private let consumer: Task<Void, Never>

    init(_ apply: @escaping @MainActor (Value) -> Void) {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self)
        self.continuation = continuation
        consumer = Task { @MainActor in
            for await value in stream {
                apply(value)
            }
        }
    }

    /// Il callback da passare al Core: si può chiamare da qualunque thread.
    var report: @Sendable (Value) -> Void {
        let continuation = continuation
        return { continuation.yield($0) }
    }

    /// Chiude il flusso e attende che ogni valore già segnalato sia stato applicato.
    func finish() async {
        continuation.finish()
        await consumer.value
    }
}
