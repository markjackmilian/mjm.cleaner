import CleanerCore
import CleanerFeatures

/// Porting di `TestHome.cs`: una cartella dati temporanea per i test che usano la composizione vera
/// (`AppEnvironment.live`). Tutto ciò che scrive sta sotto di essa e sparisce con `remove()`.
struct TestHome {
    let directory: TemporaryDirectory
    let environment: AppEnvironment

    static func create(settings: CleanerSettings? = nil) async throws -> TestHome {
        let directory = try TemporaryDirectory()
        let environment = try await AppEnvironment.live(paths: AppPaths(supportDirectory: directory.path))
        if let settings {
            try environment.settings.save(settings)
        }
        return TestHome(directory: directory, environment: environment)
    }

    func remove() {
        directory.remove()
    }
}
