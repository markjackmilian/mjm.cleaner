import AppKit
import CleanerFeatures
import SwiftUI

/// Una sola finestra (spec §6.2): 1120×700 all'apertura, almeno 900×600. «Impostazioni… ⌘,» apre
/// lo sheet della finestra principale al posto della scena `Settings` standard, che non è modale e
/// non ha Annulla.
@main
struct MjmCleanerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var startup = AppStartup()

    var body: some Scene {
        Window(Text(verbatim: "mjm.cleaner"), id: "main") {
            RootView(startup: startup)
                .frame(minWidth: 900, minHeight: 600)
                .task { await startup.start() }
        }
        .defaultSize(width: 1120, height: 700)
        .commands {
            // Apre le Impostazioni, dove compaiono stato ed esito del controllo.
            CommandGroup(after: .appInfo) {
                Button("Controlla aggiornamenti…") {
                    guard let main = startup.main, let updates = main.updates else { return }
                    main.showSettings()
                    Task { await updates.checkNow() }
                }
                .disabled(!(startup.main?.canShowSettings ?? false) || startup.main?.updates == nil || (startup.main?.updates?.isBusy ?? false))
            }
            CommandGroup(replacing: .appSettings) {
                Button("Impostazioni…") { startup.main?.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(!(startup.main?.canShowSettings ?? false))
            }
        }
    }
}

/// L'aspetto si applica prima che la finestra compaia, così non lampeggia quello sbagliato
/// (`App.axaml.cs`). L'ambiente nasce in modo asincrono: qui si legge solo la preferenza salvata.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppKitAppearance().apply(AppStartup.savedAppearance())
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Il contenuto della finestra: niente finché l'ambiente non è pronto, poi la finestra principale
/// oppure la vista d'errore (`FatalErrorWindow`).
struct RootView: View {
    let startup: AppStartup

    var body: some View {
        switch startup.state {
        case .loading:
            Color.clear
        case .ready(let main):
            MainView(main: main)
        case .failed(let message):
            StartupFailureView(message: message)
        }
    }
}
