import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per il passo 3. Il diario (spec §8.2) è nuovo.
@MainActor
struct ConfirmStepModelTests {
    private let categories = [makeCategory("logs", name: "Log e crash report"), makeCategory("archive", name: "Archivio")]

    private var results: [CategoryScanResult] {
        [
            CategoryScanResult(
                categoryId: "logs",
                items: [makeItem("/Users/tester/Library/Logs/a.log", size: 1024), makeItem("/Users/tester/Library/Logs/b.log", size: 2048)],
                totalBytes: 3072, errors: [], exclusions: []),
            // Lo stesso file proposto anche dai file grandi: una sola riga, nella prima categoria.
            CategoryScanResult(
                categoryId: "archive",
                items: [makeItem("/Users/tester/Library/Logs/b.log", size: 2048), makeItem("/Users/tester/Downloads/big.iso", size: 1_048_576)],
                totalBytes: 1_050_624, errors: [], exclusions: []),
        ]
    }

    @Test func rowsArePerPathAcrossCategoriesWithSummariesAndTotal() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: categories, results: results)

        #expect(model.nodes.map(\.displayName) == ["Log e crash report", "Archivio"])
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

        #expect(clean.selections.map { $0.map(\.categoryId) } == [["logs", "archive"]])
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

    // Voci contenute in una cartella proposta altrove (spec `2026-10-20-confirmation-containment-design.md`).

    private static let megabyte: Int64 = 1_048_576

    private let nested = [
        makeCategory("dev-caches", name: "Cache di sviluppo"),
        makeCategory("large-files", name: "File grandi", itemsSelectedByDefault: false),
    ]

    /// Il caso segnalato: con «File grandi» su `~`, il modello sta nella cache di Hugging Face.
    private var nestedResults: [CategoryScanResult] {
        [
            CategoryScanResult(
                categoryId: "dev-caches",
                items: [
                    makeItem("/Users/tester/.cache/huggingface", size: 6 * Self.megabyte, root: "/Users/tester/.cache", directory: true),
                    makeItem("/Users/tester/.cache/pip", size: Self.megabyte, root: "/Users/tester/.cache", directory: true),
                ],
                totalBytes: 7 * Self.megabyte, errors: [], exclusions: []),
            CategoryScanResult(
                categoryId: "large-files",
                items: [
                    makeItem("/Users/tester/Movies/raw.mov", size: 3 * Self.megabyte, root: "/Users/tester"),
                    makeItem("/Users/tester/.cache/huggingface/hub/model.bin", size: 5 * Self.megabyte, root: "/Users/tester"),
                ],
                totalBytes: 8 * Self.megabyte, errors: [], exclusions: []),
        ]
    }

    @Test func aRowInsideATickedFolderAppearsTickedLockedAndExplained() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: nestedResults)
        let modelRow = model.nodes[1].paths[1]

        #expect(!modelRow.isSelected)
        #expect(modelRow.isCovered)
        #expect(modelRow.isChecked)
        #expect(modelRow.containmentText
            == "Inclusa in /Users/tester/.cache/huggingface (Cache di sviluppo): si elimina con la cartella.")
        #expect(model.nodes[1].paths[0].containmentText == "")
        #expect(!model.nodes[1].paths[0].isChecked)
        #expect(model.nodes.map { $0.paths.map(\.containsText) } == [["Contiene anche 1 voce di File grandi.", ""], ["", ""]])
        #expect(model.totalText == "7 MB · 2 elementi")
    }

    @Test func untickingTheFolderFreesTheRowWithItsOwnChoice() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: nestedResults)
        let folder = model.nodes[0].paths[0]
        let modelRow = model.nodes[1].paths[1]

        folder.isSelected = false
        #expect(!modelRow.isCovered)
        #expect(!modelRow.isChecked)
        #expect(modelRow.containmentText == "Inclusa in /Users/tester/.cache/huggingface (Cache di sviluppo).")
        #expect(model.totalText == "1 MB · 1 elemento")

        modelRow.isSelected = true
        #expect(model.totalText == "6 MB · 2 elementi")

        folder.isSelected = true
        #expect(modelRow.isChecked)
        #expect(model.totalText == "7 MB · 2 elementi")
    }

    @Test func selectAllLeavesCoveredRowsToTheirFolder() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: nestedResults)
        let large = model.nodes[1]

        #expect(!large.allSelected)
        #expect(large.canSelectAll)
        #expect(large.coveredText == "1 voce è dentro una cartella spuntata e si elimina con quella.")

        large.allSelected = true
        #expect(large.paths.map(\.isSelected) == [true, false])
        #expect(large.allSelected)

        large.allSelected = false
        #expect(large.paths.map(\.isSelected) == [false, false])
        #expect(large.paths.map(\.isChecked) == [false, true])
        #expect(!large.allSelected)

        model.nodes[0].paths[0].isSelected = false
        #expect(large.coveredText == "")
        #expect(model.nodes[0].coveredText == "")
    }

    @Test func aGroupMadeOnlyOfCoveredRowsCannotSelectAll() throws {
        let results = [
            nestedResults[0],
            CategoryScanResult(
                categoryId: "large-files",
                items: [
                    makeItem("/Users/tester/.cache/huggingface/hub/model.bin", size: 5 * Self.megabyte, root: "/Users/tester"),
                    makeItem("/Users/tester/.cache/pip/wheels/torch.whl", size: Self.megabyte, root: "/Users/tester"),
                ],
                totalBytes: 6 * Self.megabyte, errors: [], exclusions: []),
        ]
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: results)
        let large = model.nodes[1]

        #expect(!large.canSelectAll)
        #expect(large.allSelected)
        #expect(large.coveredText == "2 voci sono dentro cartelle spuntate e si eliminano con quelle.")

        large.allSelected = false
        #expect(large.paths.map(\.isChecked) == [true, true])
    }

    /// Una cartella e una voce che contiene nello stesso gruppo, con la voce prima della cartella:
    /// «deseleziona tutte» raggiunge anche la voce che la cartella libera.
    @Test func selectAllReachesTheRowsThatItsOwnFolderFrees() throws {
        let results = [CategoryScanResult(
            categoryId: "large-files",
            items: [
                makeItem("/Users/tester/VM/Windows.pvm/disk.hdd", size: 4 * Self.megabyte, root: "/Users/tester"),
                makeItem("/Users/tester/VM/Windows.pvm", size: 5 * Self.megabyte, root: "/Users/tester", directory: true),
            ],
            totalBytes: 9 * Self.megabyte, errors: [], exclusions: [])]
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: results)
        let large = model.nodes[0]
        #expect(large.paths[1].containsText == "Contiene anche 1 voce di File grandi.")

        large.paths[0].isSelected = true
        large.paths[1].isSelected = true
        #expect(large.allSelected)

        large.allSelected = false
        #expect(large.paths.map(\.isSelected) == [false, false])
        #expect(!model.canDelete)
    }

    @Test func deleteSendsTheFolderAndNotTheRowsItCovers() async throws {
        let clean = FakeClean()
        let model = ConfirmStepModel(environment: try makeEnvironment(clean: clean), navigation: nil, categories: nested, results: nestedResults)
        model.nodes[1].paths[0].isSelected = true
        model.nodes[1].paths[1].isSelected = true

        await model.delete()

        #expect(clean.selections.first?.map(\.categoryId) == ["dev-caches", "large-files"])
        #expect(clean.selections.first?.map { $0.items.map(\.path) } == [
            ["/Users/tester/.cache/huggingface", "/Users/tester/.cache/pip"], ["/Users/tester/Movies/raw.mov"],
        ])
    }

    /// Le root passano dal risolutore dell'ambiente: `~/.cache` porta a `~/Dati/cache`, dove «File
    /// grandi» ha trovato il modello.
    @Test func containmentUsesTheRootsOfTheEnvironment() throws {
        let results = [
            nestedResults[0],
            CategoryScanResult(
                categoryId: "large-files",
                items: [makeItem("/Users/tester/Dati/cache/huggingface/model.bin", size: 5 * Self.megabyte, root: "/Users/tester/Dati")],
                totalBytes: 5 * Self.megabyte, errors: [], exclusions: []),
        ]
        let roots = FakeRootResolver(targets: ["/Users/tester/.cache": "/Users/tester/Dati/cache"])
        let model = ConfirmStepModel(environment: try makeEnvironment(roots: roots), navigation: nil, categories: nested, results: results)

        #expect(model.nodes[1].paths[0].isCovered)
        #expect(!ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: results).nodes[1].paths[0].isCovered)
    }

    /// La riga intermedia di una catena ha entrambe le note; la nota della voce nomina la cartella più
    /// vicina; la cartella conta le voci di ogni gruppo, nell'ordine dei gruppi.
    @Test func notesOnAChainAndOnSeveralGroups() throws {
        let groups = [
            makeCategory("g-a", name: "Gruppo A"), makeCategory("g-b", name: "Gruppo B"),
            makeCategory("g-c", name: "Gruppo C"), makeCategory("g-d", name: "Gruppo D"),
        ]
        let results = [
            CategoryScanResult(categoryId: "g-a", items: [makeItem("/Users/tester/x/a", directory: true)], totalBytes: 100, errors: [], exclusions: []),
            CategoryScanResult(categoryId: "g-b", items: [makeItem("/Users/tester/x/a/b", directory: true)], totalBytes: 100, errors: [], exclusions: []),
            CategoryScanResult(
                categoryId: "g-c", items: [makeItem("/Users/tester/x/a/b/1.bin"), makeItem("/Users/tester/x/a/b/2.bin")],
                totalBytes: 200, errors: [], exclusions: []),
            CategoryScanResult(categoryId: "g-d", items: [makeItem("/Users/tester/x/a/b/3.bin")], totalBytes: 100, errors: [], exclusions: []),
        ]
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: groups, results: results)
        let outer = model.nodes[0].paths[0]
        let middle = model.nodes[1].paths[0]

        #expect(outer.containsText == "Contiene anche 1 voce di Gruppo B.")
        #expect(middle.containmentText == "Inclusa in /Users/tester/x/a (Gruppo A): si elimina con la cartella.")
        #expect(middle.containsText == "Contiene anche 2 voci di Gruppo C. Contiene anche 1 voce di Gruppo D.")
        #expect(model.nodes[2].paths[0].containmentText == "Inclusa in /Users/tester/x/a/b (Gruppo B): si elimina con la cartella.")
        #expect(model.nodes[3].paths[0].containmentText == "Inclusa in /Users/tester/x/a/b (Gruppo B): si elimina con la cartella.")
    }

    /// La garanzia vista dall'utente, su ogni combinazione di una catena di tre cartelle e di un file
    /// libero: una casella vuota non sta mai sotto una voce inviata al motore, e una casella spuntata
    /// è inviata o sta sotto una voce inviata.
    @Test func theTicksOnScreenMatchWhatIsDeleted() async throws {
        let groups = [makeCategory("cat-1"), makeCategory("cat-2"), makeCategory("cat-3")]
        let results = [
            CategoryScanResult(
                categoryId: "cat-1", items: [makeItem("/Users/tester/x/a/b/c.bin"), makeItem("/Users/tester/x/libero.iso")],
                totalBytes: 200, errors: [], exclusions: []),
            CategoryScanResult(categoryId: "cat-2", items: [makeItem("/Users/tester/x/a", directory: true)], totalBytes: 100, errors: [], exclusions: []),
            CategoryScanResult(categoryId: "cat-3", items: [makeItem("/Users/tester/x/a/b", directory: true)], totalBytes: 100, errors: [], exclusions: []),
        ]
        func isUnder(_ path: String, _ folder: String) -> Bool { path.hasPrefix(folder + "/") }

        for mask in 0..<16 {
            let clean = FakeClean()
            let model = ConfirmStepModel(environment: try makeEnvironment(clean: clean), navigation: nil, categories: groups, results: results)
            let rows = model.nodes.flatMap(\.paths)
            for (index, row) in rows.enumerated() {
                row.isSelected = mask & (1 << index) != 0
            }

            let total = model.totalText
            await model.delete()
            let sent = clean.selections.first?.flatMap { $0.items.map(\.path) } ?? []

            for row in rows {
                let deleted = sent.contains(row.path) || sent.contains { isUnder(row.path, $0) }
                #expect(deleted == row.isChecked, "maschera \(mask): \(row.path)")
            }
            // Ogni voce pesa 100 byte: il pulsante «Elimina» conta esattamente ciò che parte.
            #expect(total == "\(100 * sent.count) B · \(sent.count) \(sent.count == 1 ? "elemento" : "elementi")", "maschera \(mask)")
        }
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

    func showSettings() {}
}
