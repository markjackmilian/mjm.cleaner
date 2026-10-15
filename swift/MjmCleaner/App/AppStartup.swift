import CleanerCore
import CleanerFeatures
import Foundation
import Observation

/// L'avvio dell'app (`App.OnFrameworkInitializationCompleted`): compone l'ambiente, crea la finestra
/// principale e legge il contatore; se la composizione fallisce (cartella dati non scrivibile,
/// database corrotto) mostra la vista d'errore con il percorso e il motivo.
@MainActor
@Observable
final class AppStartup {
    enum State {
        case loading
        case ready(MainModel)
        case failed(String)
    }

    private(set) var state = State.loading
    @ObservationIgnored private var started = false

    var main: MainModel? {
        if case .ready(let main) = state { main } else { nil }
    }

    /// La cartella dati dell'app (spec §4.4).
    static var paths: AppPaths {
        AppEnvironment.defaultPaths(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    /// La stessa lettura di `environment.settings.load()`, fatta prima che l'ambiente esista.
    static func savedAppearance() -> AppearancePreference {
        SettingsStore(fileSystem: LocalFileSystem(), paths: paths).load().appearance
    }

    func start() async {
        guard !started else { return }
        started = true

        let paths = Self.paths
        do {
            let environment = try await AppEnvironment.live(paths: paths)
            show(MainModel(environment: environment, appearance: AppKitAppearance(), folders: AppKitFolderPicker()))
        } catch {
            fail(StartupFailure.message(paths: paths, error: error))
        }
    }

    /// Mostra la finestra principale e legge il contatore «Spazio liberato». Se lo storico non si
    /// legge il contatore resta «—», come in C#.
    func show(_ main: MainModel) {
        state = .ready(main)
        Task { try? await main.refreshTotal() }
    }

    func fail(_ message: String) {
        state = .failed(message)
    }
}
