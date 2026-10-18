import CleanerCore
import Observation

/// Le destinazioni del wizard di pulizia: ogni passo chiede il successivo alla finestra principale.
@MainActor
public protocol CleanupNavigating: Navigating {
    func showScan(_ categories: [CleanupCategory])
    func showConfirm(_ categories: [CleanupCategory], results: [CategoryScanResult])
    func showDone(_ report: CleanReport, journal: PendingJournal?)
}

/// Una categoria del passo 1, con la casella di selezione.
@MainActor
@Observable
public final class CategoryChoice: Identifiable {
    public let category: CleanupCategory
    public var isSelected: Bool
    /// La prima riga del gruppo non ha separatore sopra.
    public let showSeparator: Bool

    public init(category: CleanupCategory, isSelected: Bool, showSeparator: Bool = false) {
        self.category = category
        self.isSelected = isSelected
        self.showSeparator = showSeparator
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
        let selected = choices.filter(\.isSelected).map(\.category)
        guard !selected.isEmpty else { return }

        // La selezione viene ricordata: è ciò che rende sopportabili quattro passi ogni settimana.
        // È solo una comodità: se il file non si scrive l'analisi parte comunque (in C#
        // l'eccezione chiudeva l'app; registro di parità).
        var settings = environment.settings.load()
        settings.selectedCategoryIds = selected.map(\.id)
        try? environment.settings.save(settings)

        navigation?.showScan(selected)
    }
}
