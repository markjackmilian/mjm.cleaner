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
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        return url.path(percentEncoded: false)
    }
}
