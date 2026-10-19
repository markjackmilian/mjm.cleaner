import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

@MainActor
struct UpdateModelTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Fixture {
        let model: UpdateModel
        let updater: FakeUpdater
        let store: FakeSettingsStore
        let host: FakeUpdateHost
    }

    private func create(_ change: (inout CleanerSettings) -> Void = { _ in }, updater: FakeUpdater = FakeUpdater()) -> Fixture {
        var settings = CleanerSettings()
        change(&settings)
        let store = FakeSettingsStore(settings)
        let host = FakeUpdateHost()
        let model = UpdateModel(updater: updater, settings: store, clock: FixedWallClock(now: Self.now), host: host)
        return Fixture(model: model, updater: updater, store: store, host: host)
    }

    private func newerRelease() -> FakeUpdater {
        let updater = FakeUpdater()
        updater.setCheck(.success(makeRelease()))
        return updater
    }

    // MARK: Avvio e pianificazione

    @Test func firstLaunchChecksDownloadsAndProposesTheUpdate() async {
        let fixture = create({ $0.logsMinAgeDays = 99 }, updater: newerRelease())
        await fixture.model.start()

        #expect(fixture.model.state == .ready(makeVerified()))
        #expect(fixture.model.isBannerVisible)
        #expect(fixture.store.current.lastUpdateCheck == Self.now)
        #expect(fixture.store.current.logsMinAgeDays == 99)
    }

    @Test func startRunsOnlyOnce() async {
        let updater = FakeUpdater()
        updater.setCheck(.failure(.httpStatus(403)))
        let fixture = create(updater: updater)
        await fixture.model.start()
        await fixture.model.start()
        #expect(fixture.updater.checks == 1)
    }

    @Test func automaticCheckWaitsTwentyFourHours() async {
        let fixture = create({ $0.lastUpdateCheck = Self.now.addingTimeInterval(-23 * 3600) }, updater: newerRelease())
        await fixture.model.checkIfDue()
        #expect(fixture.updater.checks == 0)
    }

    @Test func automaticCheckRunsAfterTwentyFourHours() async {
        let fixture = create({ $0.lastUpdateCheck = Self.now.addingTimeInterval(-24 * 3600) }, updater: newerRelease())
        await fixture.model.checkIfDue()
        #expect(fixture.updater.checks == 1)
    }

    @Test func disabledAutomaticChecksNeverRunButCheckNowDoes() async {
        let fixture = create({ $0.automaticUpdateChecks = false })
        await fixture.model.start()
        #expect(fixture.updater.checks == 0)

        await fixture.model.checkNow()
        #expect(fixture.updater.checks == 1)
        #expect(fixture.model.state == .upToDate)
    }

    @Test func automaticUpToDateStaysQuietAndRecordsTheCheck() async {
        let fixture = create()
        await fixture.model.checkIfDue()
        #expect(fixture.model.state == .idle)
        #expect(fixture.store.current.lastUpdateCheck == Self.now)
    }

    @Test func automaticFailureStaysQuietAndRetriesNextTime() async {
        let updater = FakeUpdater()
        updater.setCheck(.failure(.httpStatus(403)))
        let fixture = create(updater: updater)
        await fixture.model.checkIfDue()

        #expect(fixture.model.state == .idle)
        #expect(fixture.store.current.lastUpdateCheck == nil)
        await fixture.model.checkIfDue()
        #expect(updater.checks == 2)
    }

    @Test func manualFailureShowsTheReason() async {
        let updater = FakeUpdater()
        updater.setCheck(.failure(.httpStatus(403)))
        let fixture = create(updater: updater)
        await fixture.model.checkNow()
        #expect(fixture.model.state == .failed(UpdateError.httpStatus(403).errorDescription ?? ""))
    }

    @Test func automaticDownloadFailureStaysQuietButTheCheckCounts() async {
        let updater = newerRelease()
        updater.setPrepare(.failure(.digestMismatch))
        let fixture = create(updater: updater)
        await fixture.model.checkIfDue()
        #expect(fixture.model.state == .idle)
        #expect(fixture.store.current.lastUpdateCheck == Self.now)
    }

    @Test func manualDownloadFailureShowsTheReason() async {
        let updater = newerRelease()
        updater.setPrepare(.failure(.invalidBundle("firma del codice non valida")))
        let fixture = create(updater: updater)
        await fixture.model.checkNow()
        #expect(fixture.model.state == .failed(UpdateError.invalidBundle("firma del codice non valida").errorDescription ?? ""))
    }

    @Test func onlyOneCheckAtATime() async throws {
        let updater = newerRelease()
        updater.holdChecks()
        let fixture = create(updater: updater)
        let first = Task { await fixture.model.checkNow() }
        try await updater.checkStarted.wait()

        #expect(fixture.model.isBusy)
        await fixture.model.checkNow()
        await fixture.model.checkIfDue()
        updater.checkReleased.open()
        await first.value
        #expect(updater.checks == 1)
    }

    @Test func downloadedUpdateFromAPreviousSessionIsProposedWithoutChecking() async {
        let updater = newerRelease()
        updater.setCached(makeVerified("v0.3.0"))
        let fixture = create(updater: updater)
        await fixture.model.start()
        #expect(fixture.model.state == .ready(makeVerified("v0.3.0")))
        #expect(updater.checks == 0)
    }

    @Test func failedInstallIsReportedOnceAtLaunch() async {
        let updater = FakeUpdater()
        updater.setOutcome(.failed(step: "move-new"))
        let fixture = create(updater: updater)
        await fixture.model.start()

        let text = fixture.model.installFailureText ?? ""
        #expect(text.contains("move-new"))
        #expect(text.contains("0.1.0"))
        fixture.model.dismissInstallFailure()
        #expect(fixture.model.installFailureText == nil)
    }

    @Test func successfulInstallIsSilent() async {
        let updater = FakeUpdater()
        updater.setOutcome(.succeeded(AppVersion(major: 0, minor: 1, patch: 0)))
        let fixture = create(updater: updater)
        await fixture.model.start()
        #expect(fixture.model.installFailureText == nil)
    }

    @Test func downloadShowsProgressAndBlocksOtherChecks() async throws {
        let updater = newerRelease()
        updater.holdPrepare()
        let fixture = create(updater: updater)
        let running = Task { await fixture.model.checkNow() }
        try await updater.prepareStarted.wait()

        for _ in 0..<200 {
            if fixture.model.statusText == "Download dell'aggiornamento: 50%" { break }
            await Task.yield()
        }
        #expect(fixture.model.statusText == "Download dell'aggiornamento: 50%")
        #expect(fixture.model.isBusy)

        await fixture.model.checkNow()
        await fixture.model.checkIfDue()
        #expect(updater.checks == 1)

        updater.prepareReleased.open()
        await running.value
        #expect(fixture.model.state == .ready(makeVerified()))
    }

    @Test func lateProgressDoesNotHideAReadyUpdate() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        fixture.updater.sendProgress(0.9)
        for _ in 0..<50 { await Task.yield() }

        #expect(fixture.model.state == .ready(makeVerified()))
        #expect(fixture.model.isBannerVisible)
    }

    @Test func unsavedCheckIsRememberedForTheSession() async {
        let updater = FakeUpdater()
        updater.setCheck(.success(nil))
        let fixture = create(updater: updater)
        fixture.store.failSaves(with: UnexpectedTestError(description: "disco pieno"))
        await fixture.model.checkIfDue()
        await fixture.model.checkIfDue()
        #expect(updater.checks == 1)
    }

    @Test func aNewDownloadShowsTheBannerAgain() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        fixture.model.later()
        fixture.updater.failInstalls(with: .installFailed("x"))
        fixture.model.install()
        #expect(fixture.model.hasFailed)

        await fixture.model.checkNow()
        #expect(fixture.model.isBannerVisible)
    }

    // MARK: Banner

    @Test func laterHidesTheBannerAndCheckNowShowsItAgainWithoutDownloading() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        fixture.model.later()
        #expect(!fixture.model.isBannerVisible)

        await fixture.model.checkNow()
        #expect(fixture.model.isBannerVisible)
        #expect(fixture.updater.checks == 1)
    }

    @Test func automaticChecksPauseWhileAnUpdateIsReady() async throws {
        let clock = SteppedClock(Self.now)
        let updater = newerRelease()
        let store = FakeSettingsStore()
        let model = UpdateModel(updater: updater, settings: store, clock: clock, host: FakeUpdateHost())
        await model.start()
        var saved = store.current
        saved.lastUpdateCheck = Self.now.addingTimeInterval(-25 * 3600)
        try store.save(saved)
        clock.advance(by: 25 * 3600)

        await model.checkIfDue()
        #expect(updater.checks == 1)
        #expect(model.state == .ready(makeVerified()))
    }

    @Test func installLaunchesTheScriptAndQuits() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        fixture.model.install()

        #expect(fixture.updater.installs == [makeVerified()])
        #expect(fixture.model.state == .installing)
        #expect(fixture.model.isBusy)
        #expect(fixture.host.terminations == 1)
    }

    @Test func installIsRefusedWhileCleaning() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        fixture.model.isCleaning = { true }

        #expect(fixture.model.installBlockedReason != nil)
        fixture.model.install()
        #expect(fixture.updater.installs.isEmpty)
        #expect(fixture.host.terminations == 0)
    }

    @Test func manualInstallModeNeverLaunchesTheScript() async {
        let updater = newerRelease()
        updater.setMode(.manual(reason: "la cartella /Applications non è scrivibile"))
        let fixture = create(updater: updater)
        await fixture.model.start()
        fixture.model.install()
        #expect(updater.installs.isEmpty)

        fixture.model.revealUpdate()
        #expect(fixture.host.revealed == [makeVerified().bundlePath])
    }

    @Test func installThatCannotStartKeepsTheAppOpen() async {
        let updater = newerRelease()
        updater.failInstalls(with: .installFailed("script di installazione mancante"))
        let fixture = create(updater: updater)
        await fixture.model.start()
        fixture.model.install()

        #expect(fixture.model.state == .failed(UpdateError.installFailed("script di installazione mancante").errorDescription ?? ""))
        #expect(fixture.model.installFailureText?.contains("script di installazione mancante") == true)
        #expect(fixture.host.terminations == 0)
    }

    @Test func releaseNotesOpenTheReleasePage() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        fixture.model.openReleaseNotes()
        #expect(fixture.host.opened == [makeRelease().pageURL])
    }

    @Test func statusTextFollowsTheState() async {
        let fixture = create()
        #expect(fixture.model.statusText.isEmpty)
        await fixture.model.checkNow()
        #expect(fixture.model.statusText == "Hai già l'ultima versione.")

        let ready = create(updater: newerRelease())
        await ready.model.start()
        #expect(ready.model.statusText == "La versione 0.2.0 è pronta da installare.")
        #expect(ready.model.bannerTitle == "mjm.cleaner 0.2.0 è pronto da installare.")
    }

    @Test func failureStatusCarriesTheReason() async {
        let updater = FakeUpdater()
        updater.setCheck(.failure(.httpStatus(403)))
        let fixture = create(updater: updater)
        await fixture.model.checkNow()
        #expect(fixture.model.hasFailed)
        #expect(fixture.model.statusText == "Aggiornamento non riuscito: GitHub ha risposto con lo stato HTTP 403")
    }

    @Test func showsTheCurrentVersionAndTheLastCheck() {
        let fixture = create({ $0.lastUpdateCheck = Self.now })
        #expect(fixture.model.currentVersionText == "0.1.0")
        #expect(fixture.model.lastCheckText == Formatting.historyDate(Self.now))
    }
}

@MainActor
struct UpdateWiringTests {
    @Test func mainModelHasUpdatesOnlyWithAnUpdaterAndAHost() throws {
        let withBoth = MainModel(
            environment: try makeEnvironment(updater: FakeUpdater()), appearance: FakeAppearance(), folders: FakePicker(),
            updateHost: FakeUpdateHost())
        #expect(withBoth.updates != nil)

        let withoutUpdater = MainModel(
            environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker(), updateHost: FakeUpdateHost())
        #expect(withoutUpdater.updates == nil)

        let withoutHost = MainModel(environment: try makeEnvironment(updater: FakeUpdater()), appearance: FakeAppearance(), folders: FakePicker())
        #expect(withoutHost.updates == nil)
    }

    @Test func installWaitsForAnXcodeDeletionToFinish() async throws {
        let service = XcodeViewModelTests.FakeXcode(XcodeViewModelTests.snapshot(XcodeViewModelTests.candidate("device", .device)))
        let updater = FakeUpdater()
        updater.setCached(makeVerified())
        let main = MainModel(
            environment: try makeEnvironment(xcode: service, updater: updater), appearance: FakeAppearance(), folders: FakePicker(),
            updateHost: FakeUpdateHost())
        let updates = try #require(main.updates)
        await updates.start()
        main.showXcode()
        guard case .xcode(let xcode) = main.page else {
            Issue.record("La pagina Xcode non si è aperta")
            return
        }
        await xcode.initialLoad?.value
        #expect(updates.installBlockedReason == nil)

        try XcodeViewModelTests.onlyRow(xcode, .device).isSelected = true
        xcode.preview()
        let deleting = Task { await xcode.confirmDelete() }
        try await service.executionStarted.wait()

        #expect(main.isCleaning)
        #expect(updates.installBlockedReason != nil)
        updates.install()
        #expect(updater.installs.isEmpty)

        service.execution.open(XcodeViewModelTests.result())
        await deleting.value
        #expect(!main.isCleaning)
        #expect(updates.installBlockedReason == nil)
    }

    @Test func installWaitsForAWizardDeletionToFinish() async throws {
        let clean = FakeClean()
        clean.waitForCancellation()
        let updater = FakeUpdater()
        updater.setCached(makeVerified())
        let main = MainModel(
            environment: try makeEnvironment(clean: clean, updater: updater), appearance: FakeAppearance(), folders: FakePicker(),
            updateHost: FakeUpdateHost())
        let updates = try #require(main.updates)
        await updates.start()
        main.showConfirm(
            [makeCategory("logs")],
            results: [CategoryScanResult(categoryId: "logs", items: [makeItem("/Users/tester/Library/Logs/a.log")], totalBytes: 100, errors: [], exclusions: [])])
        guard case .confirm(let confirm) = main.page else {
            Issue.record("Il passo 3 non si è aperto")
            return
        }
        #expect(!main.isCleaning)

        let deleting = Task { await confirm.delete() }
        try await clean.started.wait()
        #expect(main.isCleaning)
        #expect(updates.installBlockedReason != nil)

        confirm.cancelDelete()
        await deleting.value
        #expect(!main.isCleaning)
    }

    @Test func installWaitsForADockerDeletionToFinish() async throws {
        let docker = FakeDocker()
        docker.enqueue(.success(dockerAnalysis([dockerCandidate(.image, "dangling", verdict: .delete)])))
        docker.holdExecution()
        let updater = FakeUpdater()
        updater.setCached(makeVerified())
        let main = MainModel(
            environment: try makeEnvironment(docker: docker, updater: updater), appearance: FakeAppearance(), folders: FakePicker(),
            updateHost: FakeUpdateHost())
        let updates = try #require(main.updates)
        await updates.start()
        main.showDocker()
        guard case .docker(let page) = main.page else {
            Issue.record("La pagina Docker non si è aperta")
            return
        }
        await page.initialLoad?.value
        #expect(!main.isCleaning)

        let deleting = Task { await page.delete() }
        try await docker.executionStarted.wait()
        #expect(main.isCleaning)
        #expect(updates.installBlockedReason != nil)

        docker.executionReleased.open()
        await deleting.value
        #expect(!main.isCleaning)
    }

    @Test func settingsSaveTheAutomaticCheckSwitch() {
        let store = FakeSettingsStore()
        let model = SettingsModel(store: store, appearance: FakeAppearance(), folders: FakePicker(), onSaved: {}, onClose: {})
        #expect(model.automaticUpdateChecks)
        model.automaticUpdateChecks = false
        model.save()
        #expect(store.current.automaticUpdateChecks == false)
    }

    @Test func settingsShowTheSavedAutomaticCheckSwitch() {
        var settings = CleanerSettings()
        settings.automaticUpdateChecks = false
        let model = SettingsModel(store: FakeSettingsStore(settings), appearance: FakeAppearance(), folders: FakePicker(), onSaved: {}, onClose: {})
        #expect(model.automaticUpdateChecks == false)
    }

    @Test func savingSettingsKeepsTheLastCheck() {
        var settings = CleanerSettings()
        settings.lastUpdateCheck = Date(timeIntervalSince1970: 1_790_000_000)
        let store = FakeSettingsStore(settings)
        SettingsModel(store: store, appearance: FakeAppearance(), folders: FakePicker(), onSaved: {}, onClose: {}).save()
        #expect(store.current.lastUpdateCheck == Date(timeIntervalSince1970: 1_790_000_000))
    }
}
