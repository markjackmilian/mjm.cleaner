import Foundation

/// Esegue `body` su un thread con uno stack di 64 KB, un ottavo dei 512 KB dei thread di Swift
/// Concurrency su cui l'app cancella: una visita che scende di una chiamata per livello di cartella
/// lo esaurisce con poche centinaia di livelli anche in una build ottimizzata, una visita iterativa
/// no. Così la prova sulle cartelle profonde non dipende dall'ottimizzazione della build.
func onSmallStack<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let thread = Thread {
            continuation.resume(with: Result { try body() })
        }
        thread.stackSize = 64 * 1024
        thread.start()
    }
}
