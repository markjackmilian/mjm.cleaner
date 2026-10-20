import CleanerCore
import Observation

/// Porting di `SettingsViewModel`: il contenuto dello sheet delle Impostazioni (spec §6.2). Lo
/// sheet esiste finché `MainModel.settings` non è `nil`; Salva e Annulla chiedono di chiuderlo con
/// `onClose`, che il modello principale collega all'azzeramento di quello stato.
@MainActor
@Observable
public final class SettingsModel: Identifiable {
    /// Limiti dei campi numerici della finestra C# (`Minimum`/`Maximum` dei `NumericUpDown`).
    public static let thresholdMegabytesRange = 1...100_000
    public static let minAgeDaysRange = 0...3650

    @ObservationIgnored private let store: any SettingsStoring
    @ObservationIgnored private let appearanceApplier: any AppearanceApplying
    @ObservationIgnored private let folders: any FolderPicking
    @ObservationIgnored private let onSaved: @MainActor () -> Void
    @ObservationIgnored private let onClose: @MainActor () -> Void
    @ObservationIgnored private let loadedAppearance: AppearancePreference
    @ObservationIgnored private var saved = false

    /// Byte esatti letti al caricamento, insieme al valore in MB troncato che ne deriva. Se al
    /// salvataggio il campo mostrato non è cambiato, si riscrivono questi byte invariati invece di
    /// ricalcolarli da MB: altrimenti un valore che non è multiplo esatto di un megabyte perderebbe
    /// precisione a ogni salvataggio, anche quando l'utente modifica un campo del tutto scorrelato.
    @ObservationIgnored private let loadedThresholdBytes: Int64
    @ObservationIgnored private let loadedThresholdMegabytes: Int

    /// L'aspetto scelto si vede subito: diventa definitivo solo con Salva.
    public var appearance: AppearancePreference {
        didSet {
            guard appearance != oldValue else { return }
            appearanceApplier.apply(appearance)
        }
    }

    public var projectRoots: [String]
    public var largeFileRoots: [String]
    public var selectedProjectRoot: String?
    public var selectedLargeFileRoot: String?
    /// Cartelle mai analizzate né proposte, in nessuna categoria della pulizia guidata.
    public var excludedFolders: [String]
    public var selectedExcludedFolder: String?
    public var largeFileThresholdMegabytes: Int
    public var downloadsMinAgeDays: Int
    public var logsMinAgeDays: Int
    public var nuGetMinAgeDays: Int
    /// Controllo automatico degli aggiornamenti; il pulsante «Controlla ora» è di `UpdateModel`.
    public var automaticUpdateChecks: Bool

    /// Vuoto finché un salvataggio non fallisce. In C# l'eccezione di scrittura chiudeva l'app; qui
    /// lo sheet resta aperto e dice perché (registro di parità).
    public private(set) var saveErrorText = ""

    public var hasSaveError: Bool { !saveErrorText.isEmpty }
    public var canRemoveProjectRoot: Bool { selectedProjectRoot != nil }
    public var canRemoveLargeFileRoot: Bool { selectedLargeFileRoot != nil }
    public var canRemoveExcludedFolder: Bool { selectedExcludedFolder != nil }

    public init(
        store: any SettingsStoring,
        appearance: any AppearanceApplying,
        folders: any FolderPicking,
        onSaved: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.store = store
        appearanceApplier = appearance
        self.folders = folders
        self.onSaved = onSaved
        self.onClose = onClose

        let settings = store.load()
        loadedAppearance = settings.appearance
        self.appearance = settings.appearance
        projectRoots = settings.projectRoots
        largeFileRoots = settings.largeFileRoots
        excludedFolders = settings.excludedFolders
        loadedThresholdBytes = settings.largeFileThresholdBytes
        loadedThresholdMegabytes = Int(settings.largeFileThresholdBytes / (1024 * 1024))
        largeFileThresholdMegabytes = loadedThresholdMegabytes
        downloadsMinAgeDays = settings.downloadsMinAgeDays
        logsMinAgeDays = settings.logsMinAgeDays
        nuGetMinAgeDays = settings.nuGetMinAgeDays
        automaticUpdateChecks = settings.automaticUpdateChecks
    }

    public func save() {
        // I megabyte restano nell'intervallo di un `int` del C#: il prodotto non trabocca mai.
        let megabytes = Int64(min(max(1, largeFileThresholdMegabytes), Int(Int32.max)))
        let thresholdBytes = largeFileThresholdMegabytes == loadedThresholdMegabytes
            ? loadedThresholdBytes
            : megabytes * 1024 * 1024

        var settings = store.load()
        settings.appearance = appearance
        settings.projectRoots = projectRoots
        settings.largeFileRoots = largeFileRoots
        settings.excludedFolders = excludedFolders
        settings.largeFileThresholdBytes = thresholdBytes
        settings.downloadsMinAgeDays = max(0, downloadsMinAgeDays)
        settings.logsMinAgeDays = max(0, logsMinAgeDays)
        settings.nuGetMinAgeDays = max(0, nuGetMinAgeDays)
        settings.automaticUpdateChecks = automaticUpdateChecks

        do {
            try store.save(settings)
        } catch {
            saveErrorText = String(localized: "Impostazioni non salvate: \(FeatureText.message(error))", bundle: .module)
            return
        }

        saveErrorText = ""
        saved = true
        onSaved()
        onClose()
    }

    public func cancel() {
        dismiss()
        onClose()
    }

    /// Chiusura senza salvare (Annulla o chiusura dello sheet): torna l'aspetto di prima. Idempotente.
    public func dismiss() {
        if !saved {
            appearanceApplier.apply(loadedAppearance)
        }
    }

    public func addProjectRoot() async {
        let title = String(localized: "Scegli una cartella di progetto", bundle: .module)
        if let path = await addFolder(to: \.projectRoots, title: title) {
            selectedProjectRoot = path
        }
    }

    public func removeProjectRoot() {
        if let root = selectedProjectRoot {
            remove(root, from: \.projectRoots)
        }
        selectedProjectRoot = nil
    }

    public func addLargeFileRoot() async {
        let title = String(localized: "Scegli una cartella in cui cercare file grandi", bundle: .module)
        if let path = await addFolder(to: \.largeFileRoots, title: title) {
            selectedLargeFileRoot = path
        }
    }

    public func removeLargeFileRoot() {
        if let root = selectedLargeFileRoot {
            remove(root, from: \.largeFileRoots)
        }
        selectedLargeFileRoot = nil
    }

    public func addExcludedFolder() async {
        let title = String(localized: "Scegli una cartella da escludere", bundle: .module)
        if let path = await addFolder(to: \.excludedFolders, title: title) {
            selectedExcludedFolder = path
        }
    }

    public func removeExcludedFolder() {
        if let folder = selectedExcludedFolder {
            remove(folder, from: \.excludedFolders)
        }
        selectedExcludedFolder = nil
    }

    private func addFolder(to list: ReferenceWritableKeyPath<SettingsModel, [String]>, title: String) async -> String? {
        guard let path = await folders.pickFolder(title: title) else { return nil }
        if !self[keyPath: list].contains(where: { FeatureText.same($0, path) }) {
            self[keyPath: list].append(path)
        }
        return path
    }

    private func remove(_ root: String, from list: ReferenceWritableKeyPath<SettingsModel, [String]>) {
        if let index = self[keyPath: list].firstIndex(where: { FeatureText.same($0, root) }) {
            self[keyPath: list].remove(at: index)
        }
    }
}
