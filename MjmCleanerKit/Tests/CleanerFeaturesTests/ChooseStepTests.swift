import CleanerCore
import Testing
@testable import CleanerFeatures

@MainActor
struct ChooseStepTests {
    @Test(arguments: [(0, "Nessuna categoria selezionata"), (1, "1 categoria selezionata"), (3, "3 categorie selezionate")])
    func countTextAgrees(count: Int, expected: String) {
        #expect(ChooseStepModel.countText(count) == expected)
    }

    /// Rientri e margini sono della vista (piano 4b): al modello resta sapere quali righe sono figlie.
    @Test func childRowsAreIndentedWithDeeperSeparator() {
        let child = CategoryChoice(category: makeCategory("nuget-packages", parent: "dev-caches"), isSelected: false, showSeparator: true)
        let root = CategoryChoice(category: makeCategory("logs"), isSelected: false, showSeparator: true)
        #expect(child.isChild)
        #expect(!root.isChild)
    }

    @Test(arguments: [(RiskLevel.low, "Rischio basso"), (.medium, "Rischio medio"), (.high, "Rischio alto")])
    func riskPillTextNamesTheLevel(risk: RiskLevel, expected: String) {
        #expect(CategoryChoice(category: makeCategory("logs", risk: risk), isSelected: false).riskLabel == expected)
    }

    @Test(arguments: [
        ("system-caches", "#66788F"), ("dev-caches", "#7457E8"), ("nuget-packages", "#3567D0"),
        ("project-build-output", "#1D8784"), ("logs", "#85858B"), ("trash", "#D2453A"), ("downloads", "#E8833A"),
        ("large-files", "#B5477F"),
    ])
    func tilesUseTheDesignColors(id: String, color: String) {
        #expect(CategoryVisuals.visual(for: id).designHex == color)
    }

    @Test func downloadsAndLargeFilesHaveTheirOwnTiles() {
        #expect(CategoryVisuals.visual(for: "downloads")
            == CategoryVisual(tileColorName: "TileDownloads", designHex: "#E8833A", symbolName: "arrow.down.to.line"))
        #expect(CategoryVisuals.visual(for: "large-files")
            == CategoryVisual(tileColorName: "TileLargeFiles", designHex: "#B5477F", symbolName: "scalemass"))
    }

    @Test func analyzeIsDisabledWithoutSelectionAndFollowsTheToggles() async throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = []
        let home = try await TestHome.create(settings: settings)
        defer { home.remove() }
        let model = ChooseStepModel(environment: home.environment, navigation: nil)

        #expect(!model.canAnalyze)
        #expect(model.selectedCountText == "Nessuna categoria selezionata")

        model.choices[0].isSelected = true

        #expect(model.canAnalyze)
        #expect(model.selectedCountText == "1 categoria selezionata")

        model.choices[0].isSelected = false

        #expect(!model.canAnalyze)
        #expect(model.selectedCountText == "Nessuna categoria selezionata")
    }

    // Solo Swift: selezione ricordata, colori sconosciuti, nomi degli asset del rischio.
    @Test func rememberedSelectionIsRestoredAndAnalyzeSavesItBeforeScanning() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["logs", "trash"]
        let store = FakeSettingsStore(settings)
        let navigation = CleanupNavigationSpy()
        let model = ChooseStepModel(environment: try makeEnvironment(settings: store), navigation: navigation)

        #expect(model.choices.filter(\.isSelected).map(\.category.id) == ["logs", "trash"])
        #expect(model.choices.map(\.showSeparator) == [false, true, true, true, true, true, true, true])

        model.choices.first { $0.category.id == "trash" }?.isSelected = false
        model.choices.first { $0.category.id == "system-caches" }?.isSelected = true
        model.analyze()

        #expect(store.current.selectedCategoryIds == ["system-caches", "logs"])
        #expect(navigation.events == ["scan"])
        #expect(navigation.scannedCategories.map(\.id) == ["system-caches", "logs"])
    }

    /// La categoria unica di prima non si trasforma nelle due nuove: sono ad alto rischio, e l'utente
    /// le ri-spunta.
    @Test func aRememberedDownloadsLargeSelectsNeitherNewCategory() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["logs", "downloads-large"]
        let model = ChooseStepModel(environment: try makeEnvironment(settings: FakeSettingsStore(settings)), navigation: nil)

        #expect(model.choices.filter(\.isSelected).map(\.category.id) == ["logs"])
    }

    @Test func analyzeStillScansWhenTheSelectionCannotBeSaved() throws {
        let store = FakeSettingsStore()
        store.failSaves(with: UnexpectedTestError(description: "sola lettura"))
        let navigation = CleanupNavigationSpy()
        let model = ChooseStepModel(environment: try makeEnvironment(settings: store), navigation: navigation)

        model.analyze()

        #expect(store.saves == 1)
        #expect(navigation.events == ["scan"])
    }

    @Test func unknownCategoriesGetTheNeutralTileAndRiskHasItsAsset() {
        #expect(CategoryVisuals.visual(for: "sconosciuta") == CategoryVisuals.visual(for: "logs"))
        #expect(CategoryVisuals.visual(for: "sconosciuta").tileColorName == "TileNeutral")
        #expect([RiskLevel.low, .medium, .high].map(\.colorName) == ["RiskLow", "RiskMedium", "RiskHigh"])
    }

    // Solo Swift (review del Task 5): «Analizza» senza selezione non salva né apre il passo 2, e il
    // salvataggio della selezione conserva le altre impostazioni (`Load() with { … }` del C#).
    @Test func analyzeWithNothingSelectedDoesNothing() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = []
        let store = FakeSettingsStore(settings)
        let navigation = CleanupNavigationSpy()
        let model = ChooseStepModel(environment: try makeEnvironment(settings: store), navigation: navigation)

        model.analyze()

        #expect(navigation.events.isEmpty)
        #expect(store.saves == 0)
    }

    @Test func analyzeKeepsTheOtherSettings() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["logs"]
        settings.projectRoots = ["~/code"]
        settings.logsMinAgeDays = 7
        settings.appearance = .dark
        let store = FakeSettingsStore(settings)
        let model = ChooseStepModel(environment: try makeEnvironment(settings: store), navigation: CleanupNavigationSpy())

        model.analyze()

        #expect(store.current == settings)
    }

    @Test func completeDownloadsIsOneRunAndDoesNotChangeRememberedCategoryIds() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["downloads"]
        let store = FakeSettingsStore(settings)
        let navigation = CleanupNavigationSpy()
        let environment = try makeEnvironment(settings: store)
        let model = ChooseStepModel(environment: environment, navigation: navigation)
        let downloads = try #require(model.choices.first { $0.category.id == "downloads" })
        let configuredAges = downloads.category.rules.map(\.minAge)

        #expect(downloads.isSelected)
        #expect(!downloads.emptiesDownloads)

        downloads.emptiesDownloads = true
        #expect(downloads.isSelected)
        model.analyze()

        let scannedDownloads = try #require(navigation.scannedCategories.first { $0.id == "downloads" })
        #expect(scannedDownloads.rules.map(\.minAge).allSatisfy { $0 == nil })
        #expect(scannedDownloads.itemsSelectedByDefault)
        #expect(store.current.selectedCategoryIds == ["downloads"])

        downloads.emptiesDownloads = false
        model.analyze()
        let ordinaryDownloads = try #require(navigation.scannedCategories.first { $0.id == "downloads" })
        #expect(ordinaryDownloads.rules.map(\.minAge) == configuredAges)
        #expect(!ordinaryDownloads.itemsSelectedByDefault)

        downloads.emptiesDownloads = true
        downloads.isSelected = false
        #expect(!downloads.emptiesDownloads)
        #expect(store.current.selectedCategoryIds == ["downloads"])
    }

    @Test func completeDownloadsModeIsOffWhenRememberedCategoryReturns() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["downloads"]
        let model = ChooseStepModel(environment: try makeEnvironment(settings: FakeSettingsStore(settings)), navigation: nil)

        let downloads = try #require(model.choices.first { $0.category.id == "downloads" })
        #expect(downloads.isSelected)
        #expect(!downloads.emptiesDownloads)
    }

    // Categorie senza cartelle (spec `2026-10-20-package-exclusions-folder-warning-design.md`).

    /// Senza cartelle nelle Impostazioni «Cartelle bin e obj nei progetti» e «File grandi» non hanno
    /// nulla da analizzare: anche se ricordate, partono deselezionate e con l'avviso.
    @Test func categoriesWithoutFoldersAreUnavailableEvenWhenRemembered() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["project-build-output", "logs", "large-files"]
        let model = ChooseStepModel(environment: try makeEnvironment(settings: FakeSettingsStore(settings)), navigation: nil)

        let unavailable = model.choices.filter { !$0.isAvailable }
        #expect(unavailable.map(\.category.id) == ["project-build-output", "large-files"])
        #expect(unavailable.map(\.unavailableText) == ["Nessuna cartella da analizzare.", "Nessuna cartella da analizzare."])
        #expect(model.choices.filter(\.isAvailable).allSatisfy { $0.unavailableText.isEmpty })
        #expect(model.choices.filter(\.isSelected).map(\.category.id) == ["logs"])
        #expect(model.selectedCountText == "1 categoria selezionata")
    }

    /// La casella disattivata è della vista; il modello ignora comunque una spunta, così una categoria
    /// vuota non arriva mai all'analisi né alla selezione salvata.
    @Test func selectingAnUnavailableCategoryIsIgnored() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["logs"]
        let store = FakeSettingsStore(settings)
        let navigation = CleanupNavigationSpy()
        let model = ChooseStepModel(environment: try makeEnvironment(settings: store), navigation: navigation)
        let largeFiles = try #require(model.choices.first { $0.category.id == "large-files" })

        largeFiles.isSelected = true

        #expect(!largeFiles.isSelected)
        #expect(model.selectedCountText == "1 categoria selezionata")

        model.analyze()

        #expect(navigation.scannedCategories.map(\.id) == ["logs"])
        #expect(store.current.selectedCategoryIds == ["logs"])
    }

    @Test func categoriesWithFoldersAreAvailableAndSelectable() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["project-build-output"]
        settings.projectRoots = ["~/src"]
        settings.largeFileRoots = ["~/Downloads"]
        let model = ChooseStepModel(environment: try makeEnvironment(settings: FakeSettingsStore(settings)), navigation: nil)
        let largeFiles = try #require(model.choices.first { $0.category.id == "large-files" })

        largeFiles.isSelected = true

        #expect(model.choices.allSatisfy { $0.isAvailable })
        #expect(model.choices.filter(\.isSelected).map(\.category.id) == ["project-build-output", "large-files"])
        #expect(largeFiles.unavailableText.isEmpty)
    }

    /// Anche chi costruisce una riga già spuntata non può selezionare una categoria senza regole.
    @Test func aChoiceBuiltSelectedWithoutRulesIsNotSelected() {
        let choice = CategoryChoice(category: makeCategory("large-files"), isSelected: true)

        #expect(!choice.isAvailable)
        #expect(!choice.isSelected)
    }

    /// «Apri Impostazioni…» accanto all'avviso.
    @Test func openSettingsAsksTheWindowForTheSettingsSheet() throws {
        let navigation = CleanupNavigationSpy()
        let model = ChooseStepModel(environment: try makeEnvironment(), navigation: navigation)

        model.openSettings()

        #expect(navigation.events == ["settings"])
    }
}
