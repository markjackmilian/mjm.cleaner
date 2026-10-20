import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

/// Solo Swift: la finestra principale costruisce ogni pagina con ciò che riceve e con i servizi
/// dell'ambiente, aggiorna il contatore, collega lo sheet delle Impostazioni e rifiuta anche le
/// richieste delle pagine mentre Xcode elimina (spec §6.3).
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
            engine: dockerDesktop, diskBefore: nil, diskAfter: DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil))
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

    @Test func aFailedTotalReadKeepsTheShownAmount() async throws {
        let history = FakeHistory()
        history.failReads(with: UnexpectedTestError(description: "storico illeggibile"))
        let main = MainModel(environment: try makeEnvironment(history: history), appearance: FakeAppearance(), folders: FakePicker())

        await #expect(throws: UnexpectedTestError.self) {
            try await main.refreshTotal()
        }
        #expect(main.totalFreedAmount == "—")
    }

    // MARK: Composizione e cablaggio delle pagine

    /// Ogni pagina creata dalla finestra naviga tramite la finestra: un ciclo completo del wizard
    /// partito dallo Storico, poi Docker e il suo resoconto.
    @Test func everyPageIsWiredToTheMainModel() async throws {
        let scan = FakeScan()
        scan.respond(with: [CategoryScanResult(
            categoryId: "logs", items: [makeItem("/Users/tester/Library/Logs/a.log")], totalBytes: 100, errors: [], exclusions: [])])
        let main = MainModel(environment: try makeEnvironment(scan: scan), appearance: FakeAppearance(), folders: FakePicker())

        main.select(.history)
        try #require(main.page.historyModel).close()
        let choose = try #require(main.page.chooseStep)
        choose.choices.first?.isSelected = true
        choose.analyze()
        let step = try #require(main.page.scanStep)
        // «Pulizia» nella sidebar non interrompe il ciclo in corso.
        main.select(.cleanup)
        #expect(main.page.scanStep === step)
        await step.run?.value
        let confirm = try #require(main.page.confirmStep)
        await confirm.delete()
        let done = try #require(main.page.doneStep)
        await done.persistence?.value
        done.newCleanup()
        #expect(main.page.kind == .choose)

        main.select(.docker)
        #expect(main.page.kind == .docker)
        let docker = try #require(main.page.dockerModel)
        await docker.initialLoad?.value
        docker.close()
        #expect(main.page.kind == .choose)

        main.showDockerReport(
            DockerCleanResult(report: makeReport(), before: .empty, after: nil, daemonLost: false),
            engine: dockerDesktop, diskBefore: nil, diskAfter: DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil))
        let dockerReport = try #require(main.page.dockerReportModel)
        await dockerReport.persistence?.value
        dockerReport.analyzeAgain()
        #expect(main.page.kind == .docker)
    }

    @Test func everyPageReceivesWhatTheMainModelPassesIt() async throws {
        let scan = FakeScan()
        let main = MainModel(environment: try makeEnvironment(scan: scan), appearance: FakeAppearance(), folders: FakePicker())
        let logs = makeCategory("logs", name: "Log di sistema")

        main.showScan([logs])
        let step = try #require(main.page.scanStep)
        #expect(step.progress.map(\.displayName) == ["Log di sistema"])
        await step.run?.value
        #expect(scan.scannedCategoryIds == [["logs"]])

        main.showConfirm([logs], results: [CategoryScanResult(
            categoryId: "logs", items: [makeItem("/Users/tester/Library/Logs/a.log", size: 2048)], totalBytes: 2048, errors: [], exclusions: [])])
        let confirm = try #require(main.page.confirmStep)
        #expect(confirm.nodes.map(\.displayName) == ["Log di sistema"])
        #expect(confirm.nodes.flatMap(\.paths).map(\.path) == ["/Users/tester/Library/Logs/a.log"])

        main.showDone(makeReport(bytesFreed: 2048, itemsDeleted: 1), journal: nil)
        let done = try #require(main.page.doneStep)
        #expect(done.freedText == "2 KB liberati")
        await done.persistence?.value

        main.showDockerReport(
            DockerCleanResult(report: makeReport(), before: .empty, after: nil, daemonLost: true),
            engine: dockerDesktop, diskBefore: DockerDiskUsage(path: "/Docker.raw", allocatedBytes: 4 * 1_073_741_824, apparentBytes: nil),
            diskAfter: DockerDiskUsage(path: "/Docker.raw", allocatedBytes: 3 * 1_073_741_824, apparentBytes: nil))
        let report = try #require(main.page.dockerReportModel)
        #expect(report.diskText == "Docker.raw sul disco: 4 GB → 3 GB")
        #expect(report.daemonLostText == "Docker Desktop si è fermato durante la pulizia: le voci restanti non sono state eliminate. Avvialo e premi «Nuova analisi» per riprovare.")
        await report.persistence?.value
    }

    /// Il resoconto Docker riceve il motore che gli passa la pagina: con OrbStack niente Purge né
    /// Docker.raw, anche con due misure di un disco che non cala.
    @Test func theDockerReportKeepsTheEngineItIsGiven() async throws {
        let main = MainModel(environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker())
        let orbStack = DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack")
        let disk = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: 4 * 1_073_741_824, apparentBytes: nil)

        main.showDockerReport(
            DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: nil, daemonLost: true),
            engine: orbStack, diskBefore: disk, diskAfter: disk)

        let report = try #require(main.page.dockerReportModel)
        #expect(report.diskText == "Disco virtuale: OrbStack restituisce lo spazio al Mac automaticamente.")
        #expect(report.purgeHint == "")
        #expect(report.daemonLostText == "OrbStack si è fermato durante la pulizia: le voci restanti non sono state eliminate. Avvialo e premi «Nuova analisi» per riprovare.")
        await report.persistence?.value
    }

    /// La pagina Xcode aperta dalla finestra usa servizio, storico, log di sessione e orologio
    /// dell'ambiente: il diario si apre all'ora dell'ambiente prima di `execute` e si scarta dopo il log.
    @Test func theXcodePageUsesTheEnvironmentServices() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let history = FakeHistory(events: events)
        let sessionLog = FakeSessionLog(events: events, journalDirectory: directory.path)
        let service = Self.xcodeService()
        let main = MainModel(
            environment: try makeEnvironment(history: history, sessionLog: sessionLog, xcode: service),
            appearance: FakeAppearance(), folders: FakePicker())

        let deleting = try await Self.startXcodeDeletion(main, service)
        #expect(service.receivedJournal == [true])
        service.execution.open(XcodeViewModelTests.result())
        await deleting.value
        let report = try #require(main.page.xcodeReportModel)
        await report.persist()

        let saved = XcodeViewModelTests.result().historyReport
        #expect(history.saved == [saved])
        #expect(sessionLog.written.map { $0.report } == [saved])
        // L'orologio di `makeEnvironment` (1_790_000_000) dà il nome del diario.
        #expect(sessionLog.discarded == [PathText.join(AppPaths(supportDirectory: directory.path).logsDirectory, "pending-20260921T141320Z.jsonl")])
        #expect(events.values == ["open", "save", "write", "discard", "total"])
    }

    @Test func theSettingsSheetPicksFoldersWithTheGivenPicker() async throws {
        let picker = FakePicker("/Users/tester/Progetti")
        let main = MainModel(environment: try makeEnvironment(), appearance: FakeAppearance(), folders: picker)

        main.showSettings()
        let settings = try #require(main.settings)
        await settings.addProjectRoot()

        #expect(picker.requests.count == 1)
        #expect(settings.projectRoots.contains { FeatureText.same($0, "/Users/tester/Progetti") })
    }

    // MARK: Blocco della navigazione per le pagine (spec §6.3)

    /// Sonda della revisione: un passo 2 la cui analisi termina dopo che l'utente è passato a Xcode
    /// non sostituisce la pagina Xcode mentre elimina.
    @Test func aStaleScanStepCannotReplaceTheXcodePageWhileItDeletes() async throws {
        let scan = GatedScan()
        let service = Self.xcodeService()
        let main = MainModel(environment: try makeEnvironment(scan: scan, xcode: service), appearance: FakeAppearance(), folders: FakePicker())

        main.showScan([makeCategory("logs")])
        let step = try #require(main.page.scanStep)
        try await scan.started.wait()

        let deleting = try await Self.startXcodeDeletion(main, service)

        scan.release.open()
        await step.run?.value

        #expect(main.page.kind == .xcode)
        #expect(main.isXcodeBusy)

        service.execution.open(XcodeViewModelTests.result())
        await deleting.value
        #expect(main.page.kind == .xcodeReport)
    }

    /// Revisione finale: Salva nelle Impostazioni durante l'analisi riporta al passo 1, e l'analisi
    /// vecchia non porta più al passo 3, che sarebbe calcolato senza la cartella appena esclusa.
    @Test func savingSettingsDuringTheScanDropsItsResults() async throws {
        let scan = GatedScan()
        let main = MainModel(environment: try makeEnvironment(scan: scan), appearance: FakeAppearance(), folders: FakePicker())
        main.showScan([makeCategory("logs")])
        let step = try #require(main.page.scanStep)
        try await scan.started.wait()

        main.showSettings()
        try #require(main.settings).save()
        #expect(main.page.kind == .choose)

        scan.release.open()
        await step.run?.value

        #expect(main.page.kind == .choose)
    }

    /// La stessa garanzia quando l'utente è passato a un'altra pagina prima di salvare: l'analisi
    /// continua in background, ma dopo Salva non porta più al passo 3.
    @Test func savingSettingsFromAnotherPageDropsABackgroundScan() async throws {
        let scan = GatedScan()
        let main = MainModel(environment: try makeEnvironment(scan: scan), appearance: FakeAppearance(), folders: FakePicker())
        main.showScan([makeCategory("logs")])
        let step = try #require(main.page.scanStep)
        try await scan.started.wait()

        main.showHistory()
        main.showSettings()
        try #require(main.settings).save()

        scan.release.open()
        await step.run?.value

        #expect(main.page.kind == .choose)
    }

    @Test func startOverIsRefusedWhileXcodeDeletes() async throws {
        try await Self.expectRefusedWhileXcodeDeletes(opening: .choose) { $0.startOver() }
    }

    @Test func showScanIsRefusedWhileXcodeDeletes() async throws {
        try await Self.expectRefusedWhileXcodeDeletes(opening: .scan) { $0.showScan([makeCategory("logs")]) }
    }

    @Test func showConfirmIsRefusedWhileXcodeDeletes() async throws {
        try await Self.expectRefusedWhileXcodeDeletes(opening: .confirm) { $0.showConfirm([makeCategory("logs")], results: []) }
    }

    /// Il passo 4 non sostituisce la pagina Xcode, ma la pulizia già avvenuta si salva comunque:
    /// storico, log e poi il diario scartato, prima del contatore.
    @Test func showDoneIsRefusedWhileXcodeDeletesButTheReportIsSaved() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let history = SignallingHistory(events: events)
        let sessionLog = FakeSessionLog(events: events, journalDirectory: directory.path)
        let journal = try #require(sessionLog.openJournal(startedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        let service = Self.xcodeService()
        let main = MainModel(
            environment: try makeEnvironment(history: history, sessionLog: sessionLog, xcode: service),
            appearance: FakeAppearance(), folders: FakePicker())
        let deleting = try await Self.startXcodeDeletion(main, service)
        let report = makeReport(bytesFreed: 2048, itemsDeleted: 1, deletedPaths: ["/Users/tester/Library/Caches/a"])

        main.showDone(report, journal: journal)

        #expect(main.page.kind == .xcode)
        #expect(await history.totalRead.wait(within: .seconds(5)) != nil)
        #expect(history.saved == [report])
        #expect(sessionLog.written.map { $0.report } == [report])
        #expect(sessionLog.discarded == [journal.path])
        // Il primo "open" è il diario del test, il secondo quello della pagina Xcode.
        #expect(events.values == ["open", "open", "save", "write", "discard", "total"])

        service.execution.open(XcodeViewModelTests.result())
        await deleting.value
        main.showDone(report, journal: nil)
        #expect(main.page.kind == .done)
    }

    /// Come il passo 4: il resoconto Docker non sostituisce la pagina Xcode, ma si salva.
    @Test func showDockerReportIsRefusedWhileXcodeDeletesButTheReportIsSaved() async throws {
        let events = Recorder<String>()
        let history = SignallingHistory(events: events)
        let sessionLog = FakeSessionLog(events: events)
        let service = Self.xcodeService()
        let main = MainModel(
            environment: try makeEnvironment(history: history, sessionLog: sessionLog, xcode: service),
            appearance: FakeAppearance(), folders: FakePicker())
        let deleting = try await Self.startXcodeDeletion(main, service)
        let report = makeReport(itemsDeleted: 1, deletedPaths: ["docker:volume:dati"])
        let result = DockerCleanResult(report: report, before: .empty, after: nil, daemonLost: false)
        let disk = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil)

        main.showDockerReport(result, engine: dockerDesktop, diskBefore: nil, diskAfter: disk)

        #expect(main.page.kind == .xcode)
        #expect(await history.totalRead.wait(within: .seconds(5)) != nil)
        #expect(history.saved == [report])
        #expect(sessionLog.written.map { $0.report } == [report])
        #expect(events.values == ["open", "save", "write", "total"])

        service.execution.open(XcodeViewModelTests.result())
        await deleting.value
        main.showDockerReport(result, engine: dockerDesktop, diskBefore: nil, diskAfter: disk)
        #expect(main.page.kind == .dockerReport)
    }

    // MARK: Supporto

    private static func xcodeService() -> XcodeViewModelTests.FakeXcode {
        XcodeViewModelTests.FakeXcode(XcodeViewModelTests.snapshot(XcodeViewModelTests.candidate("device", .device)))
    }

    /// Apre Xcode dalla sidebar e avvia un'eliminazione che resta sospesa finché il test non apre
    /// `service.execution`.
    private static func startXcodeDeletion(_ main: MainModel, _ service: XcodeViewModelTests.FakeXcode) async throws -> Task<Void, Never> {
        main.select(.xcode)
        let xcode = try #require(main.page.xcodeModel)
        await xcode.initialLoad?.value
        try XcodeViewModelTests.onlyRow(xcode, .device).isSelected = true
        xcode.preview()
        let deleting = Task { await xcode.confirmDelete() }
        try await service.executionStarted.wait()
        #expect(main.isXcodeBusy)
        return deleting
    }

    /// `navigate` non cambia la pagina mentre Xcode elimina; finita l'eliminazione apre `destination`.
    /// Il resoconto Xcode arriva comunque: `showXcodeReport` non è bloccato.
    private static func expectRefusedWhileXcodeDeletes(opening destination: PageKind, _ navigate: (MainModel) -> Void) async throws {
        let service = xcodeService()
        let main = MainModel(environment: try makeEnvironment(xcode: service), appearance: FakeAppearance(), folders: FakePicker())
        let deleting = try await startXcodeDeletion(main, service)

        navigate(main)
        #expect(main.page.kind == .xcode)
        #expect(main.isXcodeBusy)

        service.execution.open(XcodeViewModelTests.result())
        await deleting.value
        #expect(main.page.kind == .xcodeReport)

        navigate(main)
        #expect(main.page.kind == destination)
    }
}

/// Il modello di ciascuna pagina, per `#require`.
private extension Page {
    var chooseStep: ChooseStepModel? { if case .choose(let model) = self { model } else { nil } }
    var scanStep: ScanStepModel? { if case .scan(let model) = self { model } else { nil } }
    var confirmStep: ConfirmStepModel? { if case .confirm(let model) = self { model } else { nil } }
    var doneStep: DoneStepModel? { if case .done(let model) = self { model } else { nil } }
    var dockerModel: DockerModel? { if case .docker(let model) = self { model } else { nil } }
    var dockerReportModel: DockerReportModel? { if case .dockerReport(let model) = self { model } else { nil } }
    var xcodeModel: XcodeModel? { if case .xcode(let model) = self { model } else { nil } }
    var xcodeReportModel: XcodeReportModel? { if case .xcodeReport(let model) = self { model } else { nil } }
    var historyModel: HistoryModel? { if case .history(let model) = self { model } else { nil } }
}

/// Analisi che resta sospesa finché il test non apre `release` (al massimo 5 secondi, poi il test
/// fallisce).
private final class GatedScan: ScanPerforming {
    let started = Gate<Void>()
    let release = Gate<Void>()

    func scan(_ categories: [CleanupCategory], progress: (@Sendable (ScanProgress) -> Void)?) async throws -> [CategoryScanResult] {
        started.open()
        try? await release.wait()
        return []
    }
}

/// Storico che segnala la rilettura del contatore, l'ultimo passo del salvataggio di un resoconto:
/// così si attende anche il salvataggio di un resoconto che non diventa la pagina corrente.
private final class SignallingHistory: HistoryStoring {
    let totalRead = Gate<Void>()
    private let inner: FakeHistory

    init(events: Recorder<String>) {
        inner = FakeHistory(events: events)
    }

    var saved: [CleanReport] { inner.saved }

    func initialize() async throws {}

    func save(_ report: CleanReport) async throws -> Int64 {
        try await inner.save(report)
    }

    func sessions(limit: Int) async throws -> [CleanSessionSummary] {
        try await inner.sessions(limit: limit)
    }

    func totalBytesFreed() async throws -> Int64 {
        defer { totalRead.open() }
        return try await inner.totalBytesFreed()
    }
}
