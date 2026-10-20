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
        try await scan.started.wait()

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

    // Solo Swift (review del Task 6): in ogni ramo l'avanzamento già segnalato è applicato prima di
    // lasciare il passo (`relay.finish()` prima della navigazione).
    private var drainUpdates: [ScanProgress] {
        [
            ScanProgress(categoryId: "logs", currentPath: "/a", itemsFound: 1, bytesFound: 10),
            ScanProgress(categoryId: "logs", currentPath: "", itemsFound: 2, bytesFound: 2048),
            ScanProgress(categoryId: "trash", currentPath: "/t", itemsFound: 0, bytesFound: 0),
        ]
    }

    @Test func progressIsAppliedBeforeShowingTheConfirmStep() async throws {
        let scan = FakeScan()
        scan.respond(with: [], progress: drainUpdates)
        let navigation = SnapshotNavigation()
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: navigation, categories: categories)
        navigation.model = model

        await model.run?.value

        #expect(navigation.statusesAtNavigation == [["2 elementi · 2 KB", "in corso…"]])
        #expect(navigation.pathsAtNavigation == ["/t"])
    }

    @Test func progressIsAppliedBeforeGoingBackAfterACancel() async throws {
        let scan = FakeScan()
        scan.respond(with: [], progress: drainUpdates)
        scan.waitForCancellation()
        let navigation = SnapshotNavigation()
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: navigation, categories: categories)
        navigation.model = model
        try await scan.started.wait()

        model.cancel()
        await model.run?.value

        #expect(navigation.statusesAtNavigation == [["2 elementi · 2 KB", "in corso…"]])
    }

    @Test func progressIsAppliedWhenTheScanFails() async throws {
        let scan = FakeScan()
        scan.respond(with: [], progress: drainUpdates)
        scan.fail(with: UnexpectedTestError(description: "disco scollegato"))
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: nil, categories: categories)

        await model.run?.value

        #expect(model.progress.map(\.status) == ["2 elementi · 2 KB", "in corso…"])
    }
}

/// Fotografa il passo 2 nel momento in cui chiede di cambiare pagina.
@MainActor
private final class SnapshotNavigation: CleanupNavigating {
    weak var model: ScanStepModel?
    private(set) var statusesAtNavigation: [[String]] = []
    private(set) var pathsAtNavigation: [String] = []

    private func snapshot() {
        statusesAtNavigation.append(model?.progress.map(\.status) ?? [])
        pathsAtNavigation.append(model?.currentPath ?? "")
    }

    func startOver() { snapshot() }
    func refreshTotal() async throws {}
    func showScan(_ categories: [CleanupCategory]) {}
    func showConfirm(_ categories: [CleanupCategory], results: [CategoryScanResult]) { snapshot() }
    func showDone(_ report: CleanReport, journal: PendingJournal?) {}
    func showSettings() {}
}
