import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

@MainActor
struct XcodeReportViewModelTests {
    private typealias Fixture = XcodeViewModelTests

    private static func partialResult() -> XcodeCleanResult {
        XcodeCleanResult(
            historyReport: makeReport(),
            items: [XcodeItemResult(candidate: Fixture.candidate("device", .device), outcome: .skipped, reason: "annullata", verifiedEstimatedBytes: nil)],
            freeBytesBefore: 100, freeBytesAfter: 110, warnings: [])
    }

    private static func create(
        _ result: XcodeCleanResult,
        history: FakeHistory = FakeHistory(),
        log: FakeSessionLog = FakeSessionLog(),
        navigation: Fixture.FakeNavigation = Fixture.FakeNavigation()
    ) -> XcodeReportModel {
        XcodeReportModel(history: history, sessionLog: log, navigation: navigation, result: result, journal: nil)
    }

    @Test func cancelledPartialReportIsSavedOnce() async {
        let history = FakeHistory()
        let log = FakeSessionLog()
        let model = Self.create(Self.partialResult(), history: history, log: log)

        await model.persistence?.value
        await model.persist()

        #expect(history.saves == 1)
        #expect(log.writes == 1)
        #expect(model.items.count == 1)
    }

    @Test func unknownSizeUsesUnavailableLabel() async {
        var runtime = Fixture.candidate("runtime", .runtime)
        runtime.sizeBytes = nil
        let item = XcodeItemResult(candidate: runtime, outcome: .deleted, reason: "verified", verifiedEstimatedBytes: nil)
        let model = Self.create(XcodeCleanResult(historyReport: makeReport(), items: [item], freeBytesBefore: nil, freeBytesAfter: nil, warnings: []))

        await model.persistence?.value

        #expect(model.items.map(\.sizeText) == ["non disponibile"])
    }

    @Test func persistenceFailureShowsReportAndError() async {
        let history = FakeHistory()
        history.failSaves(with: UnexpectedTestError(description: "database bloccato"))
        let model = Self.create(Self.partialResult(), history: history)

        await model.persistence?.value
        await model.persist()

        #expect(model.historyWarning.contains("storico"))
        #expect(model.hasHistoryWarning)
        #expect(model.items.count == 1)
        #expect(history.saves == 1)
    }

    // Solo Swift: testi del resoconto, messaggi per ogni punto di arresto, navigazione.

    @Test func textsDescribeOutcomesAndFreeSpace() {
        let items = [
            XcodeItemResult(candidate: Fixture.candidate("a", .device), outcome: .deleted, reason: "verificata", verifiedEstimatedBytes: 2048),
            XcodeItemResult(candidate: Fixture.candidate("b", .device), outcome: .skipped, reason: "annullata", verifiedEstimatedBytes: nil),
            XcodeItemResult(candidate: Fixture.candidate("c", .device), outcome: .failed, reason: "errore", verifiedEstimatedBytes: nil),
            XcodeItemResult(candidate: Fixture.candidate("d", .device), outcome: .uncertain, reason: "dubbio", verifiedEstimatedBytes: nil),
        ]
        let grew = Self.create(XcodeCleanResult(
            historyReport: makeReport(bytesFreed: 1_234_567, itemsDeleted: 1), items: items,
            freeBytesBefore: 1024, freeBytesAfter: 3072, warnings: ["uno", "due"]))
        let shrank = Self.create(XcodeCleanResult(
            historyReport: makeReport(), items: [], freeBytesBefore: 3072, freeBytesAfter: 1024, warnings: []))

        #expect(grew.freedText == "1.234.567 byte stimati conteggiati nella cronologia")
        #expect(grew.summaryText == "1 eliminate · 1 saltate · 1 non riuscite · 1 incerte")
        #expect(grew.items.map(\.outcomeText) == ["Eliminata", "Saltata", "Non riuscita", "Esito incerto"])
        #expect(grew.items.map(\.sizeText) == ["2 KB", "non disponibile", "non disponibile", "non disponibile"])
        #expect(grew.items.first?.detail == "verificata")
        #expect(grew.freeSpaceText == "Spazio libero rilevato: +2 KB (1 KB → 3 KB). Variazione separata dalle stime eliminate.")
        #expect(grew.warningsText == "uno\ndue")
        #expect(grew.hasWarnings)
        #expect(shrank.freeSpaceText == "Spazio libero rilevato: 3 KB → 1 KB. La variazione può dipendere da altre attività.")
        #expect(!shrank.hasWarnings)
        #expect(Self.create(Self.partialResult()).freeSpaceText.hasPrefix("Spazio libero rilevato: +"))
        #expect(Self.create(XcodeCleanResult(historyReport: makeReport(), items: [], freeBytesBefore: nil, freeBytesAfter: 1, warnings: [])).freeSpaceText
            == "Spazio libero prima o dopo: non disponibile.")
    }

    @Test func eachFailurePointHasItsOwnMessage() async {
        let logFails = FakeSessionLog()
        logFails.failWrites(with: UnexpectedTestError(description: "disco pieno"))
        let afterLog = Self.create(Self.partialResult(), log: logFails)
        await afterLog.persistence?.value
        #expect(afterLog.historyWarning == "Cronologia salvata, ma il log di sessione non è stato aggiornato: disco pieno")

        let navigation = Fixture.FakeNavigation()
        navigation.refreshFailure = UnexpectedTestError(description: "contatore illeggibile")
        let afterRefresh = Self.create(Self.partialResult(), navigation: navigation)
        await afterRefresh.persistence?.value
        #expect(afterRefresh.historyWarning == "Cronologia e log salvati, ma il contatore cumulativo non è stato aggiornato: contatore illeggibile")

        let historyFails = FakeHistory()
        historyFails.failSaves(with: UnexpectedTestError(description: "database bloccato"))
        let beforeHistory = Self.create(Self.partialResult(), history: historyFails)
        await beforeHistory.persistence?.value
        #expect(beforeHistory.historyWarning == "Pulizia completata, ma il report non è stato salvato nello storico: database bloccato")
    }

    @Test func journalSurvivesAFailedSessionLog() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let log = FakeSessionLog(journalDirectory: directory.path)
        log.failWrites(with: UnexpectedTestError(description: "disco pieno"))
        let journal = try #require(log.openJournal(startedAt: Fixture.clock.now))
        let model = XcodeReportModel(
            history: FakeHistory(), sessionLog: log, navigation: Fixture.FakeNavigation(), result: Self.partialResult(), journal: journal)

        await model.persistence?.value

        #expect(log.discarded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: journal.path))
    }

    @Test func analyzeAgainAndCloseNavigate() async {
        let navigation = Fixture.FakeNavigation()
        let model = Self.create(Self.partialResult(), navigation: navigation)
        await model.persistence?.value

        model.analyzeAgain()
        model.close()

        #expect(navigation.events == ["refreshTotal", "xcode", "startOver"])
    }

    // Solo Swift (review del Task 10): il diario sugli altri punti di arresto, come al passo 4, e i
    // conteggi del riepilogo.
    @Test func aFailedTotalRefreshStillDiscardsTheJournal() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let log = FakeSessionLog(events: events, journalDirectory: directory.path)
        let journal = try #require(log.openJournal(startedAt: Fixture.clock.now))
        let navigation = Fixture.FakeNavigation()
        navigation.refreshFailure = UnexpectedTestError(description: "contatore illeggibile")
        let model = XcodeReportModel(
            history: FakeHistory(events: events), sessionLog: log, navigation: navigation, result: Self.partialResult(), journal: journal)

        await model.persistence?.value

        #expect(events.values == ["open", "save", "write", "discard"])
        #expect(!FileManager.default.fileExists(atPath: journal.path))
        #expect(model.historyWarning == "Cronologia e log salvati, ma il contatore cumulativo non è stato aggiornato: contatore illeggibile")
    }

    @Test func historyFailureKeepsTheJournal() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let history = FakeHistory(events: events)
        history.failSaves(with: UnexpectedTestError(description: "database bloccato"))
        let log = FakeSessionLog(events: events, journalDirectory: directory.path)
        let journal = try #require(log.openJournal(startedAt: Fixture.clock.now))
        let model = XcodeReportModel(
            history: history, sessionLog: log, navigation: Fixture.FakeNavigation(), result: Self.partialResult(), journal: journal)

        await model.persistence?.value

        #expect(events.values == ["open", "save"])
        #expect(FileManager.default.fileExists(atPath: journal.path))
    }

    @Test func summaryCountsEachOutcomeSeparately() {
        func items(_ count: Int, _ outcome: XcodeItemOutcome) -> [XcodeItemResult] {
            (0..<count).map { XcodeItemResult(candidate: Fixture.candidate("\(outcome)-\($0)", .device), outcome: outcome, reason: "", verifiedEstimatedBytes: nil) }
        }
        let model = Self.create(XcodeCleanResult(
            historyReport: makeReport(itemsDeleted: 5),
            items: items(1, .deleted) + items(2, .skipped) + items(3, .failed) + items(4, .uncertain),
            freeBytesBefore: nil, freeBytesAfter: nil, warnings: []))

        #expect(model.summaryText == "5 eliminate · 2 saltate · 3 non riuscite · 4 incerte")
    }
}
