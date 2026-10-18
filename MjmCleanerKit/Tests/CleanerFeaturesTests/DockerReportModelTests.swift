import CleanerCore
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per il resoconto Docker.
@MainActor
struct DockerReportModelTests {
    private static let gigabyte: Int64 = 1_073_741_824

    private func disk(_ allocated: Int64?) -> DockerDiskUsage {
        DockerDiskUsage(path: "/Docker.raw", allocatedBytes: allocated, apparentBytes: 64 * Self.gigabyte)
    }

    @Test func textsSummarizeTheCleanup() throws {
        let report = makeReport(
            bytesFreed: 3 * Self.gigabyte, itemsDeleted: 2, itemsFailed: 1,
            errors: [ScanError(path: "nome-volume", kind: .inUse, message: "volume is in use")],
            deletedPaths: ["docker:image:sha256:abc (nginx:1.27)", "docker:volume:dati"])
        let result = DockerCleanResult(
            report: report,
            before: DockerDfSummary(entries: [DockerDfEntry(type: "Images", sizeBytes: 5 * Self.gigabyte, reclaimableBytes: 0)]),
            after: DockerDfSummary(entries: [DockerDfEntry(type: "Images", sizeBytes: 2 * Self.gigabyte, reclaimableBytes: 0)]),
            daemonLost: true)

        let model = DockerReportModel(
            environment: try makeEnvironment(), navigation: nil, result: result,
            diskBefore: disk(4 * Self.gigabyte), diskAfter: disk(4 * Self.gigabyte))

        #expect(model.freedText == "3 GB recuperati")
        #expect(model.summaryText == "2 voci eliminate · 1 non eliminata")
        #expect(model.dfText == "docker system df: 5 GB → 2 GB")
        #expect(model.diskText == "Docker.raw sul disco: 4 GB → 4 GB")
        #expect(model.purgeHint.hasPrefix("Docker.raw non si è ridotto"))
        #expect(model.daemonLostText == "Docker si è fermato durante la pulizia: le voci restanti non sono state eliminate.")
        #expect(model.deleted == ["immagine nginx:1.27", "volume dati"])
        #expect(model.failed == ["nome-volume — volume is in use"])
        #expect(model.hasFailures)
    }

    @Test func missingMeasuresAndAShrunkDiskNeedNoHint() throws {
        let result = DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: nil, daemonLost: false)

        let shrunk = DockerReportModel(
            environment: try makeEnvironment(), navigation: nil, result: result,
            diskBefore: disk(4 * Self.gigabyte), diskAfter: disk(3 * Self.gigabyte))
        let unmeasured = DockerReportModel(
            environment: try makeEnvironment(), navigation: nil, result: result, diskBefore: nil, diskAfter: disk(nil))

        #expect(shrunk.summaryText == "1 voce eliminata")
        #expect(shrunk.dfText == "docker system df: misura finale non disponibile.")
        #expect(shrunk.purgeHint == "")
        #expect(shrunk.daemonLostText == "")
        #expect(!shrunk.hasFailures)
        #expect(unmeasured.diskText == "Docker.raw sul disco: non misurabile.")
        #expect(unmeasured.purgeHint == "")
    }

    @Test(arguments: [
        ("docker:image:sha256:abc (nginx:1.27)", "immagine nginx:1.27"),
        ("docker:image:sha256:abc (nome (con parentesi))", "immagine nome (con parentesi)"),
        ("docker:image:sha256:abc", "immagine sha256:abc"),
        ("docker:image:x (", "immagine x ("),
        ("docker:volume:dati", "volume dati"),
        ("docker:build-cache", "cache di build"),
    ])
    func logEntriesBecomeReadableNames(entry: String, expected: String) {
        #expect(DockerReportModel.describe(entry) == expected)
    }

    @Test func persistenceSavesHistoryAndLogThenRefreshesTheTotal() async throws {
        let events = Recorder<String>()
        let navigation = DockerNavigationSpy()
        let model = DockerReportModel(
            environment: try makeEnvironment(history: FakeHistory(events: events), sessionLog: FakeSessionLog(events: events)),
            navigation: navigation,
            result: DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: .empty, daemonLost: false),
            diskBefore: nil, diskAfter: disk(nil))

        await model.persistence?.value

        // Nessun diario per Docker: le rimozioni passano dalla CLI, come in C#.
        #expect(events.values == ["save", "write"])
        #expect(navigation.events == ["refreshTotal"])
        #expect(model.historyWarning == "")
    }

    @Test func persistenceFailureSaysTheCleanupHappened() async throws {
        let history = FakeHistory()
        history.failSaves(with: UnexpectedTestError(description: "database bloccato"))
        let model = DockerReportModel(
            environment: try makeEnvironment(history: history), navigation: nil,
            result: DockerCleanResult(report: makeReport(), before: .empty, after: .empty, daemonLost: false),
            diskBefore: nil, diskAfter: disk(nil))

        await model.persistence?.value

        #expect(model.historyWarning == "Pulizia completata, storico non aggiornato: database bloccato")
    }

    @Test func analyzeAgainAndCloseNavigate() throws {
        let navigation = DockerNavigationSpy()
        let model = DockerReportModel(
            environment: try makeEnvironment(), navigation: navigation,
            result: DockerCleanResult(report: makeReport(), before: .empty, after: .empty, daemonLost: false),
            diskBefore: nil, diskAfter: disk(nil))

        model.analyzeAgain()
        model.close()

        #expect(navigation.events.filter { $0 != "refreshTotal" } == ["docker", "startOver"])
    }

    // Solo Swift (review del Task 9): il Purge si suggerisce solo con eliminazioni e due misure, e il
    // salvataggio segue storico → log → contatore come nel passo 4.
    @Test func noPurgeHintWithoutDeletionsOrWithoutTheFirstMeasure() throws {
        let nothingDeleted = DockerReportModel(
            environment: try makeEnvironment(), navigation: nil,
            result: DockerCleanResult(report: makeReport(itemsDeleted: 0), before: .empty, after: .empty, daemonLost: false),
            diskBefore: disk(4 * Self.gigabyte), diskAfter: disk(4 * Self.gigabyte))
        let unmeasuredBefore = DockerReportModel(
            environment: try makeEnvironment(), navigation: nil,
            result: DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: .empty, daemonLost: false),
            diskBefore: disk(nil), diskAfter: disk(4 * Self.gigabyte))

        #expect(nothingDeleted.purgeHint == "")
        #expect(unmeasuredBefore.purgeHint == "")
    }

    @Test func persistenceWritesTheLogUnderTheSavedIdBeforeRefreshingTheTotal() async throws {
        let events = Recorder<String>()
        let sessionLog = FakeSessionLog(events: events)
        let navigation = SharedEventsNavigation(events)
        let model = DockerReportModel(
            environment: try makeEnvironment(history: FakeHistory(events: events), sessionLog: sessionLog),
            navigation: navigation,
            result: DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: .empty, daemonLost: false),
            diskBefore: nil, diskAfter: disk(nil))

        await model.persistence?.value

        #expect(events.values == ["save", "write", "refreshTotal"])
        #expect(sessionLog.written.map { $0.sessionId } == [1])
    }

    @Test func sessionLogFailureWarns() async throws {
        let sessionLog = FakeSessionLog()
        sessionLog.failWrites(with: UnexpectedTestError(description: "disco pieno"))
        let model = DockerReportModel(
            environment: try makeEnvironment(sessionLog: sessionLog), navigation: nil,
            result: DockerCleanResult(report: makeReport(), before: .empty, after: .empty, daemonLost: false),
            diskBefore: nil, diskAfter: disk(nil))

        await model.persistence?.value

        #expect(model.historyWarning == "Pulizia completata, storico non aggiornato: disco pieno")
    }
}

/// Navigazione che scrive `refreshTotal` nello stesso registro di storico e log.
@MainActor
private final class SharedEventsNavigation: DockerNavigating {
    private let events: Recorder<String>

    init(_ events: Recorder<String>) {
        self.events = events
    }

    func startOver() {}
    func refreshTotal() async throws { events.append("refreshTotal") }
    func showDocker() {}
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage) {}
}
