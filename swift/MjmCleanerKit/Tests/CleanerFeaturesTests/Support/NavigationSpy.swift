import CleanerFeatures

/// Registra le richieste di navigazione di una pagina. Le sezioni (pulizia, Docker, Xcode)
/// aggiungono le proprie destinazioni in sottoclassi.
@MainActor
class NavigationSpy: Navigating {
    private(set) var events: [String] = []
    var refreshFailure: (any Error)?

    func record(_ event: String) {
        events.append(event)
    }

    func startOver() {
        record("startOver")
    }

    func refreshTotal() async throws {
        record("refreshTotal")
        if let refreshFailure {
            throw refreshFailure
        }
    }
}
