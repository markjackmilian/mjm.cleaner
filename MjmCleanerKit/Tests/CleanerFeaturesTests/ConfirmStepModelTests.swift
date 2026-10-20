import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per il passo 3. Il diario (spec §8.2) è nuovo.
@MainActor
struct ConfirmStepModelTests {
    private let categories = [makeCategory("logs", name: "Log e crash report"), makeCategory("downloads-large", name: "Download e file grandi")]

    private var results: [CategoryScanResult] {
        [
            CategoryScanResult(
                categoryId: "logs",
                items: [makeItem("/Users/tester/Library/Logs/a.log", size: 1024), makeItem("/Users/tester/Library/Logs/b.log", size: 2048)],
                totalBytes: 3072, errors: [], exclusions: []),
            // Lo stesso file proposto anche dai file grandi: una sola riga, nella prima categoria.
            CategoryScanResult(
                categoryId: "downloads-large",
                items: [makeItem("/Users/tester/Library/Logs/b.log", size: 2048), makeItem("/Users/tester/Downloads/big.iso", size: 1_048_576)],
                totalBytes: 1_050_624, errors: [], exclusions: []),
        ]
    }

    @Test func rowsArePerPathAcrossCategoriesWithSummariesAndTotal() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: categories, results: results)

        #expect(model.nodes.map(\.displayName) == ["Log e crash report", "Download e file grandi"])
        #expect(model.nodes.map { $0.paths.map(\.path) } == [
            ["/Users/tester/Library/Logs/a.log", "/Users/tester/Library/Logs/b.log"],
            ["/Users/tester/Downloads/big.iso"],
        ])
        #expect(model.nodes.map(\.summaryText) == ["2 elementi · 3 KB", "1 elemento · 1 MB"])
        #expect(model.totalText == "1 MB · 3 elementi")
        #expect(model.exclusionsText == "")
        #expect(model.canDelete)
    }

    @Test func deselectingUpdatesTheTotalAndDisablesDeleteWhenNothingIsLeft() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: categories, results: results)

        model.nodes[1].paths[0].isSelected = false
        #expect(model.totalText == "3 KB · 2 elementi")

        for node in model.nodes {
            for path in node.paths { path.isSelected = false }
        }
        #expect(model.totalText == "0 B · 0 elementi")
        #expect(!model.canDelete)
    }

    @Test func exclusionsShowTheCountAndTheFirstFive() throws {
        let exclusions = (1...6).map { GuardExclusion(path: "/Users/tester/Library/Caches/x\($0)", reason: "protetto") }
        let scanned = [CategoryScanResult(categoryId: "logs", items: [], totalBytes: 0, errors: [], exclusions: exclusions)]
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: categories, results: scanned)

        let lines = model.exclusionsText.split(separator: "\n").map(String.init)
        #expect(lines.first == "6 elementi esclusi dalle protezioni:")
        #expect(lines.dropFirst() == ["· /Users/tester/Library/Caches/x1 — protetto", "· /Users/tester/Library/Caches/x2 — protetto",
                                      "· /Users/tester/Library/Caches/x3 — protetto", "· /Users/tester/Library/Caches/x4 — protetto",
                                      "· /Users/tester/Library/Caches/x5 — protetto"])
    }

    @Test func runningAppsWarningNamesAtMostFiveApps() async throws {
        #expect(ConfirmStepModel.runningAppsText([]) == "")
        #expect(ConfirmStepModel.runningAppsText(["Safari"]) == "Safari in esecuzione: la sua cache potrebbe rigenerarsi subito.")
        #expect(ConfirmStepModel.runningAppsText(["A", "B", "C", "D", "E", "F"])
            == "A, B, C, D, E e un'altra in esecuzione: le loro cache potrebbero rigenerarsi subito.")
        #expect(ConfirmStepModel.runningAppsText(["A", "B", "C", "D", "E", "F", "G"])
            == "A, B, C, D, E e altre 2 in esecuzione: le loro cache potrebbero rigenerarsi subito.")

        let model = ConfirmStepModel(
            environment: try makeEnvironment(runningApps: FakeRunningApps(["Xcode", "Safari"])),
            navigation: nil, categories: categories, results: results)
        await model.runningAppsCheck?.value
        #expect(model.runningAppsWarning == "Xcode, Safari in esecuzione: le loro cache potrebbero rigenerarsi subito.")
    }

    @Test func deleteOpensTheJournalBeforeCleaningAndHandsItToTheDoneStep() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let sessionLog = FakeSessionLog(journalDirectory: directory.path)
        let clean = FakeClean()
        let partial = makeReport(bytesFreed: 1024, itemsDeleted: 1)
        clean.respond(with: partial)
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(
            environment: try makeEnvironment(clean: clean, sessionLog: sessionLog),
            navigation: navigation, categories: categories, results: results)
        model.nodes[1].paths[0].isSelected = false

        await model.delete()

        #expect(sessionLog.events.values == ["open"])
        #expect(clean.receivedJournal == [true])
        #expect(clean.selections.first?.map(\.categoryId) == ["logs"])
        #expect(clean.selections.first?.first?.items.map(\.path) == ["/Users/tester/Library/Logs/a.log", "/Users/tester/Library/Logs/b.log"])
        #expect(model.deleteProgressText == "2 / 2 elementi · 0 B")
        #expect(!model.isDeleting)
        #expect(navigation.events == ["done"])
        #expect(navigation.doneReport == partial)

        let journal = try #require(navigation.doneJournal)
        let recorded = try String(contentsOfFile: journal.path, encoding: .utf8)
        #expect(recorded == "{\"path\":\"/Users/tester/Library/Logs/a.log\"}\n{\"path\":\"/Users/tester/Library/Logs/b.log\"}\n")
    }

    @Test func cancelDeleteStillShowsThePartialReport() async throws {
        let clean = FakeClean()
        clean.waitForCancellation()
        let partial = makeReport(itemsDeleted: 1)
        clean.respond(with: partial)
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(
            environment: try makeEnvironment(clean: clean), navigation: navigation, categories: categories, results: results)

        let deleting = Task { await model.delete() }
        try await clean.started.wait()

        #expect(model.isDeleting)
        #expect(model.canCancelDelete)
        #expect(!model.canDelete)

        model.cancelDelete()
        await deleting.value

        #expect(clean.observedCancellation == [true])
        #expect(navigation.events == ["done"])
        #expect(navigation.doneReport == partial)
        #expect(!model.isDeleting)
    }

    @Test func withoutAJournalTheCleanupStillRuns() async throws {
        let clean = FakeClean()
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(
            environment: try makeEnvironment(clean: clean), navigation: navigation, categories: categories, results: results)

        await model.delete()

        #expect(clean.receivedJournal == [false])
        #expect(navigation.events == ["done"])
        #expect(navigation.doneJournal == nil)
    }

    @Test func restartGoesBackToTheFirstStep() throws {
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: navigation, categories: categories, results: results)

        model.restart()

        #expect(navigation.events == ["startOver"])
    }

    /// Solo Swift (fix wave finale del 4b): «Ricomincia» durante l'eliminazione non lascia il passo;
    /// la vista lo disabilitava, ora lo rifiuta anche il modello. Annulla ferma ancora la pulizia.
    @Test func restartWhileDeletingStaysOnTheStep() async throws {
        let clean = FakeClean()
        clean.waitForCancellation()
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(
            environment: try makeEnvironment(clean: clean), navigation: navigation, categories: categories, results: results)

        let deleting = Task { await model.delete() }
        try await clean.started.wait()
        model.restart()
        #expect(navigation.events.isEmpty)

        model.cancelDelete()
        await deleting.value
        #expect(clean.observedCancellation == [true])
        #expect(navigation.events == ["done"])
    }

    // Solo Swift (review del Task 7): garanzie di sicurezza del passo che elimina.

    /// Una riga deselezionata non arriva mai a `clean`, anche se la sua categoria ha altre righe
    /// selezionate; ogni riga resta nella propria categoria.
    @Test func onlyTheSelectedRowsOfEachCategoryReachTheCleanup() async throws {
        let clean = FakeClean()
        let model = ConfirmStepModel(environment: try makeEnvironment(clean: clean), navigation: nil, categories: categories, results: results)
        model.nodes[0].paths[0].isSelected = false

        await model.delete()

        #expect(clean.selections.map { $0.map(\.categoryId) } == [["logs", "downloads-large"]])
        #expect(clean.selections.first?.map { $0.items.map(\.path) } == [["/Users/tester/Library/Logs/b.log"], ["/Users/tester/Downloads/big.iso"]])
    }

    // Download e File grandi (spec `2026-10-19-large-files-exclusions-design.md`).

    private let realData = [
        makeCategory("logs", name: "Log e crash report"),
        makeCategory("downloads", name: "Download", itemsSelectedByDefault: false),
        makeCategory("large-files", name: "File grandi", itemsSelectedByDefault: false),
    ]

    private var realDataResults: [CategoryScanResult] {
        [
            CategoryScanResult(
                categoryId: "logs", items: [makeItem("/Users/tester/Library/Logs/a.log", size: 1024)],
                totalBytes: 1024, errors: [], exclusions: []),
            CategoryScanResult(
                categoryId: "downloads", items: [makeItem("/Users/tester/Downloads/vecchio.dmg", size: 2048)],
                totalBytes: 2048, errors: [], exclusions: []),
            CategoryScanResult(
                categoryId: "large-files",
                items: [makeItem("/Users/tester/Parallels/Windows 11.pvm", size: 4096), makeItem("/Users/tester/Lavoro/immagine.iso", size: 8192)],
                totalBytes: 12_288, errors: [], exclusions: []),
        ]
    }

    @Test func downloadsAndLargeFilesStartDeselected() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: realData, results: realDataResults)

        #expect(model.nodes.map { $0.paths.map(\.isSelected) } == [[true], [false], [false, false]])
        #expect(model.nodes.map(\.itemsStartDeselected) == [false, true, true])
        #expect(model.totalText == "1 KB · 1 elemento")
    }

    @Test func withOnlyRealDataNothingIsDeletedUntilAnItemIsTicked() throws {
        let model = ConfirmStepModel(
            environment: try makeEnvironment(), navigation: nil,
            categories: Array(realData.dropFirst()), results: Array(realDataResults.dropFirst()))

        #expect(model.totalText == "0 B · 0 elementi")
        #expect(!model.canDelete)

        model.nodes[1].paths[1].isSelected = true

        #expect(model.totalText == "8 KB · 1 elemento")
        #expect(model.canDelete)
    }

    @Test func selectAllReadsAndWritesTheWholeGroup() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: realData, results: realDataResults)
        let large = model.nodes[2]

        #expect(!large.allSelected)
        large.paths[0].isSelected = true
        #expect(!large.allSelected)

        large.allSelected = true
        #expect(large.paths.map(\.isSelected) == [true, true])
        #expect(large.allSelected)

        large.allSelected = false
        #expect(large.paths.map(\.isSelected) == [false, false])
        #expect(model.nodes[0].allSelected)
        #expect(large.selectAllAccessibilityLabel == "Seleziona tutte le voci di File grandi")
    }

    @Test func aCategoryMissingFromTheCatalogStartsDeselected() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: [], results: [realDataResults[0]])

        #expect(model.nodes.map { $0.paths.map(\.isSelected) } == [[false]])
        #expect(!model.canDelete)
    }

    @Test func deleteHandsOverOnlyTheTickedRealData() async throws {
        let clean = FakeClean()
        let model = ConfirmStepModel(environment: try makeEnvironment(clean: clean), navigation: nil, categories: realData, results: realDataResults)
        model.nodes[2].paths[1].isSelected = true

        await model.delete()

        #expect(clean.selections.first?.map(\.categoryId) == ["logs", "large-files"])
        #expect(clean.selections.first?.map { $0.items.map(\.path) } == [
            ["/Users/tester/Library/Logs/a.log"], ["/Users/tester/Lavoro/immagine.iso"],
        ])
    }

    @Test func deleteWithNothingSelectedDoesNothing() async throws {
        let clean = FakeClean()
        let sessionLog = FakeSessionLog()
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(
            environment: try makeEnvironment(clean: clean, sessionLog: sessionLog), navigation: navigation, categories: categories, results: results)
        for node in model.nodes {
            for path in node.paths { path.isSelected = false }
        }

        await model.delete()

        #expect(clean.selections.isEmpty)
        #expect(sessionLog.events.values.isEmpty)
        #expect(navigation.events.isEmpty)
        #expect(!model.isDeleting)
    }

    /// Un secondo «Elimina» durante l'eliminazione non avvia una seconda pulizia né un secondo diario:
    /// Annulla ferma ancora l'unica in corso.
    @Test func secondDeleteWhileDeletingDoesNothing() async throws {
        let clean = FakeClean()
        clean.waitForCancellation()
        let sessionLog = FakeSessionLog()
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(
            environment: try makeEnvironment(clean: clean, sessionLog: sessionLog), navigation: navigation, categories: categories, results: results)

        let deleting = Task { await model.delete() }
        try await clean.started.wait()
        await model.delete()

        #expect(clean.selections.count == 1)
        #expect(sessionLog.events.values == ["open"])

        model.cancelDelete()
        await deleting.value
        #expect(clean.observedCancellation == [true])
        #expect(navigation.events == ["done"])
    }

    @Test func progressIsAppliedBeforeShowingTheDoneStep() async throws {
        let navigation = ProgressSnapshotNavigation()
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: navigation, categories: categories, results: results)
        navigation.model = model

        await model.delete()

        #expect(navigation.progressAtDone == ["3 / 3 elementi · 0 B"])
    }

    @Test func totalsSaturateInsteadOfTrapping() throws {
        let huge = [CategoryScanResult(
            categoryId: "logs",
            items: [makeItem("/Users/tester/Library/Logs/a.log", size: .max), makeItem("/Users/tester/Library/Logs/b.log", size: .max)],
            totalBytes: .max, errors: [], exclusions: [])]
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: categories, results: huge)

        #expect(model.nodes.map(\.summaryText) == ["2 elementi · 8388608 TB"])
        #expect(model.totalText == "8388608 TB · 2 elementi")
    }

    @Test func singularTextsForOneExclusionAndExactlyFiveApps() throws {
        let scanned = [CategoryScanResult(
            categoryId: "logs", items: [], totalBytes: 0, errors: [],
            exclusions: [GuardExclusion(path: "/Users/tester/Library/Caches/x", reason: "protetto")])]
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: categories, results: scanned)

        #expect(model.exclusionsText == "1 elemento escluso dalle protezioni:\n· /Users/tester/Library/Caches/x — protetto")
        #expect(ConfirmStepModel.runningAppsText(["A", "B", "C", "D", "E"])
            == "A, B, C, D, E in esecuzione: le loro cache potrebbero rigenerarsi subito.")
    }
}

/// Fotografa il testo d'avanzamento del passo 3 nel momento in cui chiede il passo 4.
@MainActor
private final class ProgressSnapshotNavigation: CleanupNavigating {
    weak var model: ConfirmStepModel?
    private(set) var progressAtDone: [String] = []

    func startOver() {}
    func refreshTotal() async throws {}
    func showScan(_ categories: [CleanupCategory]) {}
    func showConfirm(_ categories: [CleanupCategory], results: [CategoryScanResult]) {}
    func showDone(_ report: CleanReport, journal: PendingJournal?) {
        progressAtDone.append(model?.deleteProgressText ?? "")
    }
}
