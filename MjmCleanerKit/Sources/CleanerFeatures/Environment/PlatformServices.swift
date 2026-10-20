import CleanerCore

/// `IFolderPicker`: il pannello di scelta delle cartelle appartiene all'app (`NSOpenPanel`), il
/// modello chiede solo un percorso (spec §4.1, §6.6).
@MainActor
public protocol FolderPicking {
    /// Percorso locale della cartella scelta, o `nil` se l'utente annulla. Con `allowsPackages` si
    /// può scegliere anche un pacchetto macOS intero, come una macchina virtuale o un'app: serve
    /// alle cartelle escluse (spec `2026-10-20-package-exclusions-folder-warning-design.md`).
    func pickFolder(title: String, allowsPackages: Bool) async -> String?
}

/// `IAppearanceController`: l'aspetto vale per tutta l'app, quindi per ogni finestra e sheet
/// (`NSApp.appearance`, spec §6.4).
@MainActor
public protocol AppearanceApplying {
    func apply(_ preference: AppearancePreference)
}

extension AppearancePreference {
    /// Il nome dell'`NSAppearance` che l'app assegna a `NSApp.appearance` (spec §6.4); `nil` segue
    /// Impostazioni di Sistema e ne riprende i cambi in tempo reale. È `ThemeVariantFor` del C#,
    /// qui senza AppKit: l'adattatore dell'app converte solo il nome.
    public var appKitAppearanceName: String? {
        switch self {
        case .auto: nil
        case .light: "NSAppearanceNameAqua"
        case .dark: "NSAppearanceNameDarkAqua"
        }
    }
}

/// Ciò che ogni pagina chiede alla finestra principale: `IXcodeNavigation` del C# senza `GoTo`,
/// che diventa un metodo per destinazione nei protocolli delle singole sezioni.
@MainActor
public protocol Navigating: AnyObject {
    /// Torna al passo 1 del wizard.
    func startOver()

    /// Aggiorna il contatore «Spazio liberato» della sidebar.
    func refreshTotal() async throws
}

/// La vista d'errore mostrata quando la composizione fallisce all'avvio (`FatalErrorWindow`):
/// cartella dati non scrivibile, database corrotto. Dice cosa è andato storto e dove.
public enum StartupFailure {
    public static var title: String {
        String(localized: "Impossibile accedere ai dati dell'applicazione", bundle: .module)
    }

    public static func message(paths: AppPaths, error: any Error) -> String {
        let reason = FeatureText.message(error)
        return String(localized: "Percorso: \(paths.supportDirectory)\n\nMotivo: \(reason)", bundle: .module)
    }
}
