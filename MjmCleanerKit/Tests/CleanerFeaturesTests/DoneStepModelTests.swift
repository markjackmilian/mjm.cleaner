import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per il passo 4. L'ordine storico → log → diario è la regola
/// della spec §8.2.
@MainActor
struct DoneStepModelTests {
    @Test func textsDescribeTheReport() throws {
        let report = makeReport(
            bytesFreed: 2048, itemsDeleted: 3, duration: .milliseconds(2500),
            categories: [
                CategoryCleanResult(categoryId: "logs", bytesFreed: 2048, itemsDeleted: 3),
                CategoryCleanResult(categoryId: "trash", bytesFreed: 0, itemsDeleted: 0),
                CategoryCleanResult(categoryId: "sconosciuta", bytesFreed: 5, itemsDeleted: 1),
            ])
        let model = DoneStepModel(environment: try makeEnvironment(), navigation: nil, report: report, journal: nil)

        #expect(model.freedText == "2 KB liberati")
        #expect(model.summaryText == "in 3 secondi · 3 elementi eliminati")
        #expect(model.rows == ["Log e crash report — 2 KB", "sconosciuta — 5 B"])
        #expect(model.errorsText == "")
    }

    @Test(arguments: [
        ([ScanErrorKind.inUse, .accessDenied], "Alcuni richiedono l'Accesso completo al disco: Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco."),
        ([.notFound, .inUse], "Alcuni erano in uso da applicazioni aperte."),
        ([.notFound, .other], "Dettagli nel log della sessione."),
    ])
    func errorsTextPointsToTheLikelyCause(kinds: [ScanErrorKind], expected: String) throws {
        let errors = kinds.map { ScanError(path: "/x", kind: $0, message: "m") }
        let report = makeReport(itemsDeleted: 1, itemsFailed: errors.count, errors: errors)
        let model = DoneStepModel(environment: try makeEnvironment(), navigation: nil, report: report, journal: nil)

        #expect(model.errorsText == "2 elementi non eliminati. \(expected)")
    }

    @Test func persistenceSavesHistoryThenTheLogThenDiscardsTheJournal() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let sessionLog = FakeSessionLog(events: events, journalDirectory: directory.path)
        let journal = try #require(sessionLog.openJournal(startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        let navigation = CleanupNavigationSpy()
        let model = DoneStepModel(
            environment: try makeEnvironment(history: FakeHistory(events: events), sessionLog: sessionLog),
            navigation: navigation, report: makeReport(itemsDeleted: 1), journal: journal)

        await model.persistence?.value

        #expect(events.values == ["open", "save", "write", "discard"])
        #expect(navigation.events == ["refreshTotal"])
        #expect(!FileManager.default.fileExists(atPath: journal.path))
        #expect(model.historyWarning == "")
    }

    @Test func historyFailureKeepsTheJournalAndSaysTheCleanupHappened() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let history = FakeHistory(events: events)
        history.failSaves(with: UnexpectedTestError(description: "database bloccato"))
        let sessionLog = FakeSessionLog(events: events, journalDirectory: directory.path)
        let journal = try #require(sessionLog.openJournal(startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        let model = DoneStepModel(
            environment: try makeEnvironment(history: history, sessionLog: sessionLog),
            navigation: CleanupNavigationSpy(), report: makeReport(itemsDeleted: 1), journal: journal)

        await model.persistence?.value

        #expect(events.values == ["open", "save"])
        #expect(FileManager.default.fileExists(atPath: journal.path))
        #expect(model.historyWarning == "Pulizia completata, storico non aggiornato: database bloccato")
    }

    @Test func sessionLogFailureKeepsTheJournal() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let sessionLog = FakeSessionLog(events: events, journalDirectory: directory.path)
        sessionLog.failWrites(with: UnexpectedTestError(description: "disco pieno"))
        let journal = try #require(sessionLog.openJournal(startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        let model = DoneStepModel(
            environment: try makeEnvironment(history: FakeHistory(events: events), sessionLog: sessionLog),
            navigation: CleanupNavigationSpy(), report: makeReport(itemsDeleted: 1), journal: journal)

        await model.persistence?.value

        #expect(events.values == ["open", "save", "write"])
        #expect(sessionLog.discarded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: journal.path))
        #expect(model.historyWarning == "Pulizia completata, storico non aggiornato: disco pieno")
    }

    @Test func newCleanupStartsOver() throws {
        let navigation = CleanupNavigationSpy()
        let model = DoneStepModel(environment: try makeEnvironment(), navigation: navigation, report: makeReport(), journal: nil)

        model.newCleanup()

        #expect(navigation.events.contains("startOver"))
    }

    // Solo Swift (review del Task 8): il log scritto prima di scartare il diario è quello della
    // sessione salvata — stesso resoconto, con i percorsi eliminati, sotto l'id restituito dallo storico.
    @Test func theSessionLogReceivesTheSavedReportUnderItsId() async throws {
        let history = FakeHistory()
        let sessionLog = FakeSessionLog()
        let report = makeReport(
            bytesFreed: 2048, itemsDeleted: 2,
            deletedPaths: ["/Users/tester/Library/Logs/a.log", "/Users/tester/Library/Logs/b.log"])
        let model = DoneStepModel(
            environment: try makeEnvironment(history: history, sessionLog: sessionLog), navigation: nil, report: report, journal: nil)

        await model.persistence?.value

        #expect(history.saved == [report])
        #expect(sessionLog.written.map { $0.sessionId } == [1])
        #expect(sessionLog.written.map { $0.report } == [report])
    }

    /// Un contatore che non si aggiorna non trattiene il diario: storico e log sono già scritti.
    @Test func aFailedTotalRefreshStillDiscardsTheJournal() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let sessionLog = FakeSessionLog(events: events, journalDirectory: directory.path)
        let journal = try #require(sessionLog.openJournal(startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        let navigation = CleanupNavigationSpy()
        navigation.refreshFailure = UnexpectedTestError(description: "contatore illeggibile")
        let model = DoneStepModel(
            environment: try makeEnvironment(history: FakeHistory(events: events), sessionLog: sessionLog),
            navigation: navigation, report: makeReport(itemsDeleted: 1), journal: journal)

        await model.persistence?.value

        #expect(events.values == ["open", "save", "write", "discard"])
        #expect(navigation.events == ["refreshTotal"])
        #expect(!FileManager.default.fileExists(atPath: journal.path))
        // Stesso testo del C#, dove RefreshTotalAsync stava nello stesso try.
        #expect(model.historyWarning == "Pulizia completata, storico non aggiornato: contatore illeggibile")
    }
}
