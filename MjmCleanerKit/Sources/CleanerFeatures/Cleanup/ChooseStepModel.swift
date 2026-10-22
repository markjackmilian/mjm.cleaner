import CleanerCore
import Observation

/// Le destinazioni del wizard di pulizia: ogni passo chiede il successivo alla finestra principale.
@MainActor
public protocol CleanupNavigating: Navigating {
    func showScan(_ categories: [CleanupCategory])
    func showConfirm(_ categories: [CleanupCategory], results: [CategoryScanResult])
    func showDone(_ report: CleanReport, journal: PendingJournal?)
    /// Lo sheet delle Impostazioni, dal passo 1: per scegliere le cartelle di una categoria che non
    /// ne ha.
    func showSettings()
}

/// Una categoria del passo 1, con la casella di selezione.
@MainActor
@Observable
public final class CategoryChoice: Identifiable {
    public let category: CleanupCategory
    /// La prima riga del gruppo non ha separatore sopra.
    public let showSeparator: Bool

    /// Vero se la categoria ha qualcosa da analizzare. «Cartelle bin e obj nei progetti» e «File
    /// grandi» prendono le regole dalle cartelle scelte nelle Impostazioni: senza cartelle non ne
    /// hanno, e un'analisi non troverebbe nulla senza dire perché (spec
    /// `2026-10-20-package-exclusions-folder-warning-design.md`).
    public let isAvailable: Bool

    private var selected: Bool
    private var completeDownloads = false

    public init(category: CleanupCategory, isSelected: Bool, showSeparator: Bool = false) {
        self.category = category
        self.showSeparator = showSeparator
        isAvailable = !category.rules.isEmpty
        selected = isSelected
    }

    /// Una categoria non disponibile non risulta mai selezionata, né dalla selezione ricordata né da
    /// un'assegnazione: così resta fuori dal contatore, dall'analisi e dalla selezione salvata. La
    /// casella disattivata è della vista; questa è la garanzia.
    public var isSelected: Bool {
        get { selected && isAvailable }
        set {
            selected = newValue
            if !newValue { completeDownloads = false }
        }
    }

    /// Modalità valida solo per Download e solo finché la categoria resta selezionata.
    public var emptiesDownloads: Bool {
        get { completeDownloads }
        set {
            guard category.id == "downloads" else { return }
            completeDownloads = newValue
            if newValue { isSelected = true }
        }
    }

    var categoryForAnalysis: CleanupCategory {
        emptiesDownloads && isSelected ? category.forCompleteDownloads() : category
    }

    /// L'avviso del passo 1 per una categoria senza cartelle; vuoto se la categoria è disponibile.
    public var unavailableText: String {
        isAvailable ? "" : String(localized: "Nessuna cartella da analizzare.", bundle: .module)
    }

    public var displayName: String { category.displayName }
    public var description: String { category.description }
    public var risk: RiskLevel { category.risk }
    public var riskLabel: String { category.risk.label }
    public var visual: CategoryVisual { CategoryVisuals.visual(for: category.id) }

    /// I pacchetti NuGet compaiono rientrati sotto le cache di sviluppo.
    public var isChild: Bool { category.parentId != nil }
}

/// Porting di `ChooseStepViewModel`: passo 1, scelta delle categorie.
@MainActor
@Observable
public final class ChooseStepModel {
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored weak var navigation: (any CleanupNavigating)?

    public let choices: [CategoryChoice]

    public init(environment: AppEnvironment, navigation: (any CleanupNavigating)?) {
        self.environment = environment
        self.navigation = navigation

        let remembered = Set(environment.settings.load().selectedCategoryIds.map(FeatureText.ordinalKey))
        choices = environment.categories().enumerated().map { index, category in
            CategoryChoice(
                category: category,
                isSelected: remembered.contains(FeatureText.ordinalKey(category.id)),
                showSeparator: index > 0)
        }
    }

    public var selectedCount: Int { choices.filter(\.isSelected).count }
    public var selectedCountText: String { Self.countText(selectedCount) }
    public var canAnalyze: Bool { selectedCount > 0 }

    public static func countText(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "Nessuna categoria selezionata", bundle: .module)
        case 1: String(localized: "1 categoria selezionata", bundle: .module)
        default: String(localized: "\(String(count)) categorie selezionate", bundle: .module)
        }
    }

    public func analyze() {
        let selectedChoices = choices.filter(\.isSelected)
        let selected = selectedChoices.map(\.categoryForAnalysis)
        guard !selected.isEmpty else { return }

        // La selezione viene ricordata: è ciò che rende sopportabili quattro passi ogni settimana.
        // È solo una comodità: se il file non si scrive l'analisi parte comunque (in C#
        // l'eccezione chiudeva l'app; registro di parità).
        var settings = environment.settings.load()
        settings.selectedCategoryIds = selected.map(\.id)
        try? environment.settings.save(settings)

        navigation?.showScan(selected)
    }

    /// «Apri Impostazioni…» accanto all'avviso di una categoria senza cartelle. Dopo Salva la
    /// finestra ricrea il passo 1, con le categorie calcolate sulle impostazioni nuove.
    public func openSettings() {
        navigation?.showSettings()
    }
}
