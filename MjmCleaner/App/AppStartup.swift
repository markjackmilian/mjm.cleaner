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

    /// L'app in esecuzione per l'updater: `nil` per le build Debug (`com.mjm.cleaner.debug`).
    static var updateContext: UpdateContext? {
        UpdateContext.make(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            shortVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            bundlePath: Bundle.main.bundleURL.path(percentEncoded: false),
            processIdentifier: ProcessInfo.processInfo.processIdentifier)
    }

    /// La stessa lettura di `environment.settings.load()`, fatta prima che l'ambiente esista.
    static func savedAppearance() -> AppearancePreference {
        #if DEBUG
        if let demo = DemoLaunch.current { return demo.appearance }
        // Una pagina demo sconosciuta non legge le impostazioni vere: `start()` la rifiuta.
        if DemoLaunch.isRequested { return .auto }
        #endif
        return SettingsStore(fileSystem: LocalFileSystem(), paths: paths).load().appearance
    }

    func start() async {
        guard !started else { return }
        started = true

        #if DEBUG
        if let demo = DemoLaunch.current {
            demo.open(into: self)
            return
        }
        // Chi chiede la demo non ottiene mai l'app vera, nemmeno con una pagina che non esiste.
        if DemoLaunch.isRequested {
            fail(DemoLaunch.unknownPageMessage)
            return
        }
        #endif

        let paths = Self.paths
        do {
            let environment = try await AppEnvironment.live(paths: paths, update: Self.updateContext)
            show(MainModel(
                environment: environment, appearance: AppKitAppearance(), folders: AppKitFolderPicker(),
                updateHost: AppKitUpdateHost()))
        } catch {
            fail(StartupFailure.message(paths: paths, error: error))
        }
    }

    /// Mostra la finestra principale e legge il contatore «Spazio liberato». Se lo storico non si
    /// legge il contatore resta «—», come in C#.
    func show(_ main: MainModel) {
        state = .ready(main)
        Task { try? await main.refreshTotal() }
        // Aggiornamenti: all'avvio, poi un tick all'ora; il modello decide se il controllo è dovuto.
        if let updates = main.updates {
            Task {
                await updates.start()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3600))
                    await updates.checkIfDue()
                }
            }
        }
    }

    func fail(_ message: String) {
        state = .failed(message)
    }
}
