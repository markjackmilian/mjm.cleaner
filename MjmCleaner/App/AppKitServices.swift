import AppKit
import CleanerCore
import CleanerFeatures
import UniformTypeIdentifiers

/// `AppearanceController`: l'aspetto vale per tutta l'app, quindi per ogni finestra e per gli
/// sheet. Con `nil` macOS segue Impostazioni di Sistema in tempo reale (spec §6.4).
@MainActor
struct AppKitAppearance: AppearanceApplying {
    func apply(_ preference: AppearancePreference) {
        NSApp.appearance = preference.appKitAppearanceName.flatMap { NSAppearance(named: NSAppearance.Name($0)) }
    }
}

/// `StorageFolderPicker`: il pannello di sistema. Il percorso resta testo invariato (spec §6.6); in
/// fase 2 qui si salverà anche il bookmark.
///
/// Di norma solo cartelle: un pacchetto (`.app`, `.pvm`, `.logarchive`…) compare come un file
/// grigio. Con `allowsPackages` il pacchetto si sceglie intero, senza entrarci, e i file normali
/// restano grigi: lo scanner tratta i pacchetti come unità, e al passo 3 il pacchetto escluso
/// compare con il suo nome e il motivo «cartella esclusa nelle Impostazioni». `.utm` e
/// `.vmwarevm` senza le loro app risultano `public.folder` (sonda dei tipi del 2026-10-20) e si
/// scelgono come cartelle.
@MainActor
struct AppKitFolderPicker: FolderPicking {
    func pickFolder(title: String, allowsPackages: Bool) async -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = allowsPackages
        if allowsPackages {
            panel.allowedContentTypes = [.package]
        }
        panel.treatsFilePackagesAsDirectories = false
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

/// Gli aggiornamenti chiedono all'app di chiudersi (lo script attende la fine del processo), di
/// mostrare il bundle scaricato nel Finder e di aprire la pagina della release.
@MainActor
struct AppKitUpdateHost: UpdateHosting {
    func terminate() {
        NSApp.terminate(nil)
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
