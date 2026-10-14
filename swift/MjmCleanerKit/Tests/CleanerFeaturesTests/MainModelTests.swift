import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

/// Solo Swift: la finestra principale costruisce ogni pagina, aggiorna il contatore e collega lo
/// sheet delle Impostazioni.
@MainActor
struct MainModelTests {
    @Test func startsOnStepOneAndRefreshesTheTotal() async throws {
        let history = FakeHistory()
        history.setTotal(1_288_490_189)
        let main = MainModel(environment: try makeEnvironment(history: history), appearance: FakeAppearance(), folders: FakePicker())

        #expect(main.page.kind == .choose)
        #expect(main.section == .cleanup)
        #expect(main.totalFreedAmount == "—")

        try await main.refreshTotal()

        #expect(main.totalFreedAmount == "1,2 GB")
    }

    @Test func stepOneNavigatesThroughTheMainModel() throws {
        let main = MainModel(environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker())
        guard case .choose(let choose) = main.page else {
            Issue.record("La finestra non parte dal passo 1")
            return
        }

        choose.choices.first?.isSelected = true
        choose.analyze()

        #expect(main.page.kind == .scan)
    }

    @Test func everyDestinationBuildsItsPage() throws {
        let main = MainModel(environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker())
        let logs = makeCategory("logs")

        main.showScan([logs])
        #expect(main.page.kind == .scan)
        main.showConfirm([logs], results: [])
        #expect(main.page.kind == .confirm)
        main.showDone(makeReport(), journal: nil)
        #expect(main.page.kind == .done)
        main.showDockerReport(
            DockerCleanResult(report: makeReport(), before: .empty, after: nil, daemonLost: false),
            diskBefore: nil, diskAfter: DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil))
        #expect(main.page.kind == .dockerReport)
        #expect(main.section == .docker)

        let report = XcodeReportModel(
            history: FakeHistory(), sessionLog: FakeSessionLog(), navigation: main,
            result: XcodeViewModelTests.result(), journal: nil)
        main.showXcodeReport(report)
        guard case .xcodeReport(let shown) = main.page else {
            Issue.record("Il resoconto Xcode non è la pagina corrente")
            return
        }
        #expect(shown === report)
        #expect(main.section == .xcode)

        main.startOver()
        #expect(main.page.kind == .choose)
    }

    @Test func theDoneStepReceivesTheJournalAndDiscardsItAfterTheLog() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let sessionLog = FakeSessionLog(journalDirectory: directory.path)
        let journal = try #require(sessionLog.openJournal(startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        let main = MainModel(environment: try makeEnvironment(sessionLog: sessionLog), appearance: FakeAppearance(), folders: FakePicker())

        main.showDone(makeReport(itemsDeleted: 1), journal: journal)
        guard case .done(let done) = main.page else {
            Issue.record("Il passo 4 non è la pagina corrente")
            return
        }
        await done.persistence?.value

        #expect(sessionLog.discarded == [journal.path])
        #expect(sessionLog.events.values == ["open", "write", "discard"])
    }

    @Test func sidebarSelectionCreatesANewPageEachTime() throws {
        let main = MainModel(environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker())

        main.select(.docker)
        guard case .docker(let first) = main.page else {
            Issue.record("Docker non si è aperto")
            return
        }
        main.select(.docker)
        guard case .docker(let second) = main.page else {
            Issue.record("Docker non si è riaperto")
            return
        }
        #expect(first !== second)

        main.select(.history)
        #expect(main.section == .history)
        main.select(.xcode)
        #expect(main.section == .xcode)
        main.select(.cleanup)
        #expect(main.page.kind == .choose)
    }

    @Test func savingSettingsReturnsToStepOneAndCancelKeepsThePage() throws {
        var initial = CleanerSettings()
        initial.appearance = .light
        let store = FakeSettingsStore(initial)
        let appearance = FakeAppearance()
        let main = MainModel(environment: try makeEnvironment(settings: store), appearance: appearance, folders: FakePicker())

        main.showHistory()
        main.showSettings()
        main.settings?.appearance = .dark
        main.settings?.cancel()
        #expect(main.settings == nil)
        #expect(main.page.kind == .history)
        #expect(appearance.applied == [.dark, .light])

        main.showSettings()
        main.settings?.appearance = .dark
        main.settings?.save()
        #expect(main.settings == nil)
        #expect(main.page.kind == .choose)
        #expect(store.current.appearance == .dark)
    }
}
