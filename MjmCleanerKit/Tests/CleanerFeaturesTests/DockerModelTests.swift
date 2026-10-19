import CleanerCore
import Synchronization
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per la pagina Docker. La selezione di gruppo che salta i
/// volumi con nome è il follow-up del registro del piano 2.
@MainActor
struct DockerModelTests {
    private static let mixed = [
        dockerCandidate(.image, "dangling", verdict: .delete),
        dockerCandidate(.image, "built", verdict: .ask),
        dockerCandidate(.image, "unused", verdict: .propose),
        dockerCandidate(.volume, "anonymous", verdict: .propose, rule: "anonymous-unused"),
        dockerCandidate(.volume, "named", verdict: .propose, rule: "named-unused"),
        dockerCandidate(.image, "running", verdict: .keep),
    ]

    /// Una pagina già caricata con un'analisi che restituisce `candidates`.
    private func loaded(_ candidates: [DockerCandidate] = mixed, docker: FakeDocker = FakeDocker(), navigation: DockerNavigationSpy? = nil) async throws -> DockerModel {
        docker.enqueue(.success(dockerAnalysis(candidates)))
        return try await opened(docker: docker, navigation: navigation)
    }

    /// Una pagina caricata con le analisi già preparate in `docker`.
    private func opened(docker: FakeDocker, navigation: DockerNavigationSpy? = nil) async throws -> DockerModel {
        let model = DockerModel(environment: try makeEnvironment(docker: docker), navigation: navigation)
        await model.initialLoad?.value
        return model
    }

    private func group(_ model: DockerModel, _ id: String) throws -> DockerGroupNode {
        try #require(model.groups.first { $0.definition.id == id })
    }

    @Test func analysisFillsTheSummaryAndTheGroups() async throws {
        var settings = CleanerSettings()
        settings.projectRoots = ["~/src"]
        let docker = FakeDocker()
        docker.enqueue(.success(dockerAnalysis(Self.mixed, df: DockerDfSummary(entries: [
            DockerDfEntry(type: "Images", sizeBytes: 2 * 1_073_741_824, reclaimableBytes: 1_073_741_824),
            DockerDfEntry(type: "Containers", sizeBytes: 10, reclaimableBytes: 0),
            DockerDfEntry(type: "Local Volumes", sizeBytes: 512 * 1_048_576, reclaimableBytes: 0),
            DockerDfEntry(type: "Build Cache", sizeBytes: 1_073_741_824, reclaimableBytes: 1_073_741_824),
        ]))))
        let model = DockerModel(environment: try makeEnvironment(settings: FakeSettingsStore(settings), docker: docker), navigation: nil)

        #expect(model.isLoading)
        await model.initialLoad?.value

        #expect(docker.analyzedRoots == [["/Users/tester/src"]])
        #expect(!model.isLoading)
        #expect(model.isReady)
        #expect(model.serverText == "Docker Desktop · Docker 27.3.1 in esecuzione")
        #expect(model.diskText == "Docker.raw occupa 4 GB sul disco (dimensione apparente 64 GB: è il limite massimo del disco virtuale, non lo spazio usato).")
        #expect(model.dfText == "Immagini 2 GB (recuperabili 1 GB) · Volumi 512 MB (recuperabili 0 B) · Cache di build 1 GB (recuperabili 1 GB)")
        #expect(model.groups.map(\.definition.id) == ["safe", "local-builds", "unused-images", "unused-volumes", "keep"])
        #expect(model.groups.map(\.isExpanded) == [true, true, true, true, false])
        #expect(model.groups.map(\.showGroupCheckBox) == [true, true, true, true, false])
        #expect(model.groups.map(\.groupCheckBoxLabel).prefix(2) == ["Elimina in blocco", "Seleziona tutte"])
        let volumes = try group(model, "unused-volumes")
        #expect(volumes.summaryText == "2 voci · 200 MB")
        // Solo le voci sicure partono selezionate.
        #expect(model.totalText == "100 MB · 1 voce")
        #expect(model.canDelete)
    }

    @Test func groupSelectionNeverPicksANamedVolume() async throws {
        let model = try await loaded()
        let volumes = try group(model, "unused-volumes")
        let anonymous = try #require(volumes.rows.first { $0.candidate.id == "anonymous" })
        let named = try #require(volumes.rows.first { $0.candidate.id == "named" })

        volumes.isSelected = true

        #expect(anonymous.isSelected)
        #expect(!named.isSelected)
        #expect(named.requiresIndividualConfirmation)
        #expect(model.selection().map(\.id) == ["dangling", "anonymous"])

        // Il volume con nome entra solo con la sua casella.
        named.isSelected = true
        #expect(model.selection().map(\.id) == ["dangling", "anonymous", "named"])
        #expect(volumes.isSelected)

        // Togliere il gruppo lascia il volume con nome com'è: lo si deseleziona solo a mano.
        volumes.isSelected = false
        #expect(!anonymous.isSelected)
        #expect(named.isSelected)
    }

    @Test func aGroupOfOnlyNamedVolumesHasNoGroupCheckBox() async throws {
        let model = try await loaded([dockerCandidate(.volume, "named", verdict: .propose, rule: "named-unused")])
        let volumes = try group(model, "unused-volumes")
        #expect(!volumes.showGroupCheckBox)
    }

    @Test func rowsAndTheirGroupStayInSync() async throws {
        let model = try await loaded([
            dockerCandidate(.image, "one", verdict: .propose),
            dockerCandidate(.image, "two", verdict: .propose),
        ])
        let images = try group(model, "unused-images")

        images.isSelected = true
        #expect(images.rows.map(\.isSelected) == [true, true])

        images.rows[0].isSelected = false
        #expect(!images.isSelected)
        #expect(images.rows[1].isSelected)

        images.rows[0].isSelected = true
        #expect(images.isSelected)
        #expect(model.totalText == "200 MB · 2 voci")
    }

    @Test func blockGroupCountsWholeAndKeptResourcesAreNeverSelected() async throws {
        let model = try await loaded()
        let safe = try group(model, "safe")
        let keep = try group(model, "keep")

        safe.isSelected = false
        #expect(model.selection().isEmpty)
        #expect(!model.canDelete)

        // Una voce KEEP spuntata a mano non arriva comunque all'esecutore.
        keep.rows[0].isSelected = true
        keep.isSelected = true
        #expect(model.selection().isEmpty)
        #expect(model.totalText == "0 B · 0 voci")
    }

    @Test func unavailableDockerShowsItsMessageAndRetryLoadsAgain() async throws {
        let docker = FakeDocker()
        docker.enqueue(.failure(DockerUnavailableError(DockerUnavailableError.notRunning)))
        docker.enqueue(.success(dockerAnalysis(Self.mixed)))
        let model = try await opened(docker: docker)

        #expect(model.errorText == "Docker non è in esecuzione. Avvia il motore Docker (Docker Desktop, OrbStack…) e premi Riprova.")
        #expect(model.hasError)
        #expect(!model.isReady)
        #expect(model.canRetry)

        await model.retry()

        #expect(!model.hasError)
        #expect(model.isReady)
        #expect(model.groups.count == 5)
    }

    /// Solo Swift (fix wave finale del 4b): «Riprova» durante l'analisi non ne avvia un'altra; la
    /// vista lo disabilitava con `canRetry`, ora lo rifiuta anche il modello.
    @Test func retryWhileLoadingDoesNothing() async throws {
        let docker = SlowFirstAnalysisDocker(dockerAnalysis(Self.mixed))
        let model = DockerModel(environment: try makeEnvironment(docker: docker), navigation: nil)
        try await docker.started.wait()
        #expect(!model.canRetry)

        await model.retry()
        #expect(docker.analyses == 1)

        docker.release.open()
        await model.initialLoad?.value
        #expect(model.isReady)
        #expect(docker.analyses == 1)
    }

    /// Solo Swift (fix wave finale del 4b): hanno una casella solo le righe dei gruppi a selezione; i
    /// blocchi si spuntano interi e le voci da tenere si guardano soltanto.
    @Test func onlySelectableGroupsHaveRowCheckBoxes() async throws {
        let model = try await loaded()
        #expect(model.groups.map { $0.rows.map(\.showCheckBox) } == [[false], [true], [true], [true, true], [false]])
    }

    @Test func otherAnalysisFailuresArePrefixed() async throws {
        let docker = FakeDocker()
        docker.enqueue(.failure(UnexpectedTestError(description: "JSON non valido")))
        let model = try await opened(docker: docker)

        #expect(model.errorText == "Analisi di Docker non riuscita: JSON non valido")
    }

    @Test func deleteExecutesTheSelectionAndShowsTheReport() async throws {
        let docker = FakeDocker()
        let result = DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: nil, daemonLost: false)
        docker.respond(with: .success(result))
        let after = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: 3 * 1_073_741_824, apparentBytes: 64 * 1_073_741_824)
        docker.setDiskAfter(after)
        let navigation = DockerNavigationSpy()
        let model = try await loaded(docker: docker, navigation: navigation)

        await model.delete()

        #expect(docker.executed.map { $0.map(\.id) } == [["dangling"]])
        #expect(docker.measuredEngines == [dockerDesktop])
        #expect(model.deleteProgressText == "1 / 1 · nome-dangling")
        #expect(navigation.events == ["dockerReport"])
        #expect(navigation.reportResult == result)
        #expect(navigation.reportDiskBefore == dockerAnalysis([]).disk)
        #expect(navigation.reportDiskAfter == after)
        #expect(!model.isDeleting)
    }

    @Test(arguments: [
        (DockerUnavailableError("Docker si è fermato.") as any Error, "Docker si è fermato."),
        (UnexpectedTestError(description: "timeout") as any Error, "Pulizia non riuscita: timeout"),
    ])
    func deleteFailuresAreShownOnThePage(error: any Error, expected: String) async throws {
        let docker = FakeDocker()
        docker.respond(with: .failure(error))
        let navigation = DockerNavigationSpy()
        let model = try await loaded(docker: docker, navigation: navigation)

        await model.delete()

        #expect(model.deleteErrorText == expected)
        #expect(model.hasDeleteError)
        #expect(!model.isDeleting)
        #expect(navigation.events.isEmpty)
    }

    @Test func diskDescriptionsCoverMissingAndUnmeasurableImages() {
        #expect(DockerModel.describeDisk(DockerDiskUsage(path: "/x", allocatedBytes: nil, apparentBytes: nil), engine: dockerDesktop)
            == "Disco virtuale di Docker Desktop non trovato: lo spazio occupato sul Mac non è misurabile.")
        #expect(DockerModel.describeDisk(DockerDiskUsage(path: "/x", allocatedBytes: nil, apparentBytes: 10), engine: dockerDesktop)
            == "Docker.raw trovato, ma lo spazio occupato non è misurabile.")
        #expect(DockerModel.typeLabel("Altro") == "Altro")
    }

    @Test(arguments: [
        (DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack"),
         "OrbStack · Docker 29.8.2 in esecuzione",
         "OrbStack restituisce da solo al Mac lo spazio liberato: il suo disco virtuale non viene misurato."),
        (DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04"),
         "Docker 29.8.2 in esecuzione su «Ubuntu 24.04»",
         "Disco virtuale di questo motore non misurato: fa fede docker system df."),
        (DockerEngine(serverVersion: "29.8.2", operatingSystem: ""),
         "Docker 29.8.2 in esecuzione",
         "Disco virtuale di questo motore non misurato: fa fede docker system df."),
    ])
    func summaryNamesTheEngineAndItsDisk(engine: DockerEngine, server: String, disk: String) async throws {
        let docker = FakeDocker()
        docker.enqueue(.success(dockerAnalysis(Self.mixed, engine: engine, disk: nil)))
        let model = try await opened(docker: docker)

        #expect(model.serverText == server)
        #expect(model.diskText == disk)
    }

    /// Dopo la pulizia il disco si misura per il motore dell'analisi: con OrbStack non c'è nulla da
    /// misurare e il resoconto non riceve misure.
    @Test func theDiskAfterTheCleanupBelongsToTheEngineOfTheAnalysis() async throws {
        let orbStack = DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack")
        let docker = FakeDocker()
        docker.enqueue(.success(dockerAnalysis(Self.mixed, engine: orbStack, disk: nil)))
        docker.setDiskAfter(nil)
        let navigation = DockerNavigationSpy()
        let model = try await opened(docker: docker, navigation: navigation)

        await model.delete()

        #expect(docker.measuredEngines == [orbStack])
        #expect(navigation.events == ["dockerReport"])
        #expect(navigation.reportDiskBefore == nil)
        #expect(navigation.reportDiskAfter == nil)
    }

    @Test func rowTextsNameKindSizeAndCost() async throws {
        let model = try await loaded([
            dockerCandidate(.volume, "named", verdict: .propose, rule: "named-unused", size: nil, cost: "dati persi"),
            dockerCandidate(.buildCache, "cache", verdict: .delete),
        ])
        let named = try #require(group(model, "unused-volumes").rows.first)
        let cache = try #require(group(model, "safe").rows.first)

        #expect(named.kindLabel == "volume")
        #expect(named.sizeText == "—")
        #expect(named.detailText == "motivo · costo: dati persi · si conferma solo singolarmente")
        #expect(named.showCheckBox)
        #expect(cache.kindLabel == "cache")
        #expect(cache.detailText == "motivo")
        #expect(!cache.showCheckBox)
    }

    @Test func closeGoesBackToTheFirstStep() async throws {
        let navigation = DockerNavigationSpy()
        let model = try await loaded(navigation: navigation)

        model.close()

        #expect(navigation.events == ["startOver"])
    }

    // Solo Swift (review del Task 9): garanzie di ciò che la pagina consegna a Docker.

    /// Il tipo fa parte della chiave di riga: un volume con nome che si chiama come la cache di
    /// build non eredita la riga della cache (spuntata nel gruppo a blocco).
    @Test func volumeNamedLikeTheBuildCacheIsNotSelected() async throws {
        let model = try await loaded([
            dockerCandidate(.buildCache, "build-cache", verdict: .delete),
            dockerCandidate(.volume, "build-cache", verdict: .propose, rule: "named-unused"),
        ])

        #expect(model.selection().map(\.kind) == [.buildCache])
    }

    @Test func deleteWithoutSelectionExecutesNothing() async throws {
        let docker = FakeDocker()
        let navigation = DockerNavigationSpy()
        let model = try await loaded([dockerCandidate(.image, "dangling", verdict: .delete)], docker: docker, navigation: navigation)
        try group(model, "safe").isSelected = false

        await model.delete()

        #expect(docker.executed.isEmpty)
        #expect(navigation.events.isEmpty)
    }

    @Test func secondDeleteIsRefusedAndCancelReachesTheExecutor() async throws {
        let docker = SequencedDocker(dockerAnalysis([dockerCandidate(.image, "dangling", verdict: .delete)]))
        docker.waitForCancellation()
        let model = DockerModel(environment: try makeEnvironment(docker: docker), navigation: nil)
        await model.initialLoad?.value

        let first = Task { await model.delete() }
        try await docker.started.wait()
        #expect(model.isDeleting)
        #expect(!model.canDelete)
        await model.delete()
        model.cancelDelete()
        await first.value

        #expect(docker.events.values.filter { $0 == "execute" }.count == 1)
        #expect(docker.observedCancellation == [true])
        #expect(!model.isDeleting)
    }

    /// Il disco si misura dopo l'esecuzione: misurato prima, il resoconto mostrerebbe un disco
    /// invariato e suggerirebbe il Purge. L'esecuzione resta trattenuta finché il test non la
    /// rilascia: una misura avviata insieme all'esecuzione la trova sempre ancora in corso.
    @Test func diskIsMeasuredAfterTheExecution() async throws {
        let docker = SequencedDocker(dockerAnalysis([dockerCandidate(.image, "dangling", verdict: .delete)]))
        docker.waitForRelease()
        let navigation = DockerNavigationSpy()
        let model = DockerModel(environment: try makeEnvironment(docker: docker), navigation: navigation)
        await model.initialLoad?.value

        let deleting = Task { await model.delete() }
        try await docker.started.wait()
        #expect(docker.events.values == ["execute"])
        docker.release.open()
        await deleting.value

        #expect(docker.events.values == ["execute", "measure"])
        #expect(navigation.reportDiskAfter?.allocatedBytes == Optional(Int64(1)))
    }

    /// La misura finale non eredita l'annullamento di chi ha chiamato `delete()` (il C# usava
    /// `CancellationToken.None`): le voci sono già state rimosse, il resoconto va comunque mostrato.
    @Test func aCancelledCallerStillGetsTheReport() async throws {
        let docker = SequencedDocker(dockerAnalysis([dockerCandidate(.image, "dangling", verdict: .delete)]))
        docker.waitForRelease()
        let navigation = DockerNavigationSpy()
        let model = DockerModel(environment: try makeEnvironment(docker: docker), navigation: navigation)
        await model.initialLoad?.value

        let deleting = Task { await model.delete() }
        try await docker.started.wait()
        deleting.cancel()
        docker.release.open()
        await deleting.value

        #expect(docker.events.values == ["execute", "measure"])
        #expect(navigation.events == ["dockerReport"])
        #expect(model.deleteErrorText == "")
    }
}

/// La prima analisi resta sospesa finché il test non apre `release`; le successive rispondono subito.
private final class SlowFirstAnalysisDocker: DockerCleanupServing {
    let started = Gate<Void>()
    let release = Gate<Void>()
    private let analysis: DockerAnalysis
    private let count = Mutex(0)

    init(_ analysis: DockerAnalysis) {
        self.analysis = analysis
    }

    var analyses: Int { count.withLock { $0 } }

    func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let number = count.withLock { count -> Int in
            count += 1
            return count
        }
        if number == 1 {
            started.open()
            try await release.wait()
        }
        return analysis
    }

    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        DockerCleanResult(report: makeReport(), before: .empty, after: .empty, daemonLost: false)
    }

    func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil)
    }
}

/// Docker che registra l'ordine delle chiamate, misura un disco diverso dopo l'esecuzione e, se
/// richiesto, resta sospeso nell'esecuzione finché il test non apre `release` (al massimo 5 secondi,
/// poi il test fallisce) o finché non viene annullato (al massimo 5 secondi). Come `DiskUsageProbe`,
/// la misura fallisce in un task annullato.
private final class SequencedDocker: DockerCleanupServing {
    private struct State {
        var executed = false
        var waitsForRelease = false
        var waitsForCancellation = false
        var observedCancellation: [Bool] = []
    }

    let events = Recorder<String>()
    let started = Gate<Void>()
    let release = Gate<Void>()
    private let analysis: DockerAnalysis
    private let state = Mutex(State())

    init(_ analysis: DockerAnalysis) {
        self.analysis = analysis
    }

    var observedCancellation: [Bool] { state.withLock { $0.observedCancellation } }

    func waitForRelease() { state.withLock { $0.waitsForRelease = true } }
    func waitForCancellation() { state.withLock { $0.waitsForCancellation = true } }

    func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        analysis
    }

    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        events.append("execute")
        started.open()
        if state.withLock({ $0.waitsForRelease }) {
            try? await release.wait()
        }
        if state.withLock({ $0.waitsForCancellation }) {
            try? await Task.sleep(for: .seconds(5))
            let cancelled = Task.isCancelled
            state.withLock { $0.observedCancellation.append(cancelled) }
        }
        state.withLock { $0.executed = true }
        return DockerCleanResult(report: makeReport(itemsDeleted: selected.count), before: .empty, after: .empty, daemonLost: false)
    }

    /// Sul main actor, come la pagina: una misura avviata insieme all'esecuzione si accoda prima che il
    /// test riprenda da `started`, quindi la trova sempre ancora trattenuta da `release`.
    @MainActor
    func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        // Come `DiskUsageProbe`: `ProcessRunner.run` comincia con `Task.checkCancellation()`.
        try Task.checkCancellation()
        events.append("measure")
        let executed = state.withLock { $0.executed }
        return DockerDiskUsage(path: "/Docker.raw", allocatedBytes: executed ? 1 : 999, apparentBytes: 10)
    }
}
