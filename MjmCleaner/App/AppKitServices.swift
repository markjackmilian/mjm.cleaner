import AppKit
import CleanerCore
import CleanerFeatures

/// `AppearanceController`: l'aspetto vale per tutta l'app, quindi per ogni finestra e per gli
/// sheet. Con `nil` macOS segue Impostazioni di Sistema in tempo reale (spec §6.4).
@MainActor
struct AppKitAppearance: AppearanceApplying {
    func apply(_ preference: AppearancePreference) {
        NSApp.appearance = preference.appKitAppearanceName.flatMap { NSAppearance(named: NSAppearance.Name($0)) }
    }
}

/// `StorageFolderPicker`: il pannello di sistema, solo cartelle. Il percorso resta testo invariato
/// (spec §6.6); in fase 2 qui si salverà anche il bookmark.
@MainActor
struct AppKitFolderPicker: FolderPicking {
    func pickFolder(title: String) async -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        // Come `StorageFolderPicker(window)` del C#: un foglio della finestra attiva (lo sheet delle
        // Impostazioni), che resta bloccata finché non si sceglie o si annulla. Senza finestra attiva,
        // un pannello modale. Un pannello libero lascerebbe chiudere le Impostazioni e perderebbe la
        // cartella scelta dopo.
        let response = if let window = NSApp.keyWindow {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        guard response == .OK, let url = panel.url else { return nil }
        return url.path(percentEncoded: false)
    }
}
