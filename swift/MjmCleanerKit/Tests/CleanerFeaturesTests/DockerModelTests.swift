import CleanerCore
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
        #expect(model.serverText == "Docker 27.3.1 in esecuzione")
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

        #expect(model.errorText == "Docker non è in esecuzione. Avvia Docker Desktop e premi Riprova.")
        #expect(model.hasError)
        #expect(!model.isReady)
        #expect(model.canRetry)

        await model.retry()

        #expect(!model.hasError)
        #expect(model.isReady)
        #expect(model.groups.count == 5)
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
        #expect(DockerModel.describeDisk(DockerDiskUsage(path: "/x", allocatedBytes: nil, apparentBytes: nil))
            == "Disco virtuale di Docker Desktop non trovato: lo spazio occupato sul Mac non è misurabile.")
        #expect(DockerModel.describeDisk(DockerDiskUsage(path: "/x", allocatedBytes: nil, apparentBytes: 10))
            == "Docker.raw trovato, ma lo spazio occupato non è misurabile.")
        #expect(DockerModel.typeLabel("Altro") == "Altro")
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
}
