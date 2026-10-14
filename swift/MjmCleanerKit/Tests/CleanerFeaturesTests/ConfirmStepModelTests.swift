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
        await clean.started.wait()

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
}
