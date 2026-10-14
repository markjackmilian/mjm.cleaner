import CleanerCore
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per il passo 2.
@MainActor
struct ScanStepModelTests {
    private let categories = [makeCategory("logs", name: "Log e crash report"), makeCategory("trash", name: "Cestino")]

    @Test func progressUpdatesTheRowsAndASuccessfulScanShowsTheConfirmStep() async throws {
        let scan = FakeScan()
        let results = [CategoryScanResult(categoryId: "logs", items: [makeItem("/Users/tester/Library/Logs/a.log")], totalBytes: 100, errors: [], exclusions: [])]
        scan.respond(with: results, progress: [
            ScanProgress(categoryId: "logs", currentPath: "/Users/tester/Library/Logs/a.log", itemsFound: 1, bytesFound: 100),
            ScanProgress(categoryId: "logs", currentPath: "", itemsFound: 2, bytesFound: 2048),
            ScanProgress(categoryId: "trash", currentPath: "/Users/tester/.Trash/x", itemsFound: 0, bytesFound: 0),
            ScanProgress(categoryId: "sconosciuta", currentPath: "/ignorato", itemsFound: 9, bytesFound: 9),
        ])
        let navigation = CleanupNavigationSpy()
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: navigation, categories: categories)

        #expect(model.progress.map(\.status) == ["in attesa", "in attesa"])
        #expect(model.isRunning)

        await model.run?.value

        #expect(model.progress.map(\.displayName) == ["Log e crash report", "Cestino"])
        #expect(model.progress.map(\.status) == ["2 elementi · 2 KB", "in corso…"])
        #expect(model.currentPath == "/Users/tester/.Trash/x")
        #expect(!model.isRunning)
        #expect(!model.hasError)
        #expect(scan.scannedCategoryIds == [["logs", "trash"]])
        #expect(navigation.events == ["confirm"])
        #expect(navigation.confirmedResults == results)
    }

    @Test func cancelReturnsToTheFirstStep() async throws {
        let scan = FakeScan()
        scan.waitForCancellation()
        let navigation = CleanupNavigationSpy()
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: navigation, categories: categories)
        await scan.started.wait()

        model.cancel()
        await model.run?.value

        #expect(navigation.events == ["startOver"])
        #expect(!model.isRunning)
        #expect(!model.hasError)
    }

    @Test func failureShowsTheReasonAndOnlyTheWayBack() async throws {
        let scan = FakeScan()
        scan.fail(with: UnexpectedTestError(description: "disco scollegato"))
        let navigation = CleanupNavigationSpy()
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: navigation, categories: categories)

        await model.run?.value

        #expect(model.errorText == "Analisi non riuscita: disco scollegato")
        #expect(model.hasError)
        #expect(!model.isRunning)
        #expect(navigation.events.isEmpty)

        model.backToStart()
        #expect(navigation.events == ["startOver"])
    }

    @Test func singleItemUsesTheSingularNoun() async throws {
        let scan = FakeScan()
        scan.respond(with: [], progress: [ScanProgress(categoryId: "trash", currentPath: "", itemsFound: 1, bytesFound: 10)])
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: nil, categories: categories)

        await model.run?.value

        #expect(model.progress.map(\.status) == ["in attesa", "1 elemento · 10 B"])
    }
}
