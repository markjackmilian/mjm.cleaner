import Testing
@testable import CleanerCore

struct DockerClassifierTests {
    private func classifyRealCase(_ references: ProjectReferences = .empty) throws -> [DockerCandidate] {
        try DockerClassifier.classify(DockerFixtures.snapshot(), references)
    }

    private func find(_ candidates: [DockerCandidate], _ displayName: String) throws -> DockerCandidate {
        let matching = candidates.filter { $0.displayName == displayName }
        #expect(matching.count == 1)
        return try #require(matching.first)
    }

    // MARK: - Il caso reale: l'esito atteso dal brief, risorsa per risorsa

    @Test(arguments: [
        ("mcr.microsoft.com/mssql/server:2025-latest", DockerVerdict.keep, "in-use"),
        ("mcr.microsoft.com/azure-storage/azurite:3.35.0", .keep, "in-use"),
        ("testcontainers/ryuk:0.14.0", .delete, "tool-recreated"),
        ("dcptun_developer_ms:0.25.13", .delete, "tool-recreated"),
        ("mcr.microsoft.com/azurelinux/base/core:3.0", .delete, "tool-recreated"),
        ("mcr.microsoft.com/mssql/server:2022-latest", .propose, "superseded"),
        ("quay.io/keycloak/keycloak:26.6", .propose, "unused"),
        ("mcr.microsoft.com/mssql-tools:latest", .propose, "unused"),
        ("alpine:3.20", .propose, "unused"),
        ("orbit-api:dev", .ask, "locally-built"),
        ("mssql2025-data", .keep, "mounted"),
        ("orbit.apphost-48d90b1972-storage-data", .keep, "mounted"),
        ("orbit.apphost-48d90b1972-sql-data", .keep, "aspire-current"),
        ("orbit.apphost-48d90b1972-keycloak-data", .keep, "aspire-current"),
        ("orbit.apphost-751ef8e8e6-storage-data", .propose, "aspire-stale"),
        (DockerFixtures.anonymousVolume, .propose, "anonymous"),
    ])
    func realCaseMatchesTheExpectedOutcome(displayName: String, verdict: DockerVerdict, ruleId: String) throws {
        let candidate = try find(classifyRealCase(), displayName)

        #expect(candidate.verdict == verdict)
        #expect(candidate.ruleId == ruleId)
    }

    @Test func everyResourceOfTheRealCaseIsClassifiedOnce() throws {
        let candidates = try classifyRealCase()

        // 10 immagini + 6 volumi + la cache di build.
        #expect(candidates.count == 17)
        #expect(Set(candidates.map { "\($0.kind)|\($0.id)" }).count == candidates.count)
    }

    @Test func supersededVersionNamesTheTagInUse() throws {
        let mssql2022 = try find(classifyRealCase(), "mcr.microsoft.com/mssql/server:2022-latest")

        #expect(mssql2022.reason.contains("versione superata"))
        #expect(mssql2022.reason.contains("2025-latest"))
        #expect(mssql2022.cost.contains("riscaricare"))
    }

    @Test func stoppedContainerWithExitCode137StillKeepsItsImage() throws {
        let mssql2025 = try find(classifyRealCase(), "mcr.microsoft.com/mssql/server:2025-latest")

        #expect(mssql2025.reason.contains("sqlserver2025"))
        #expect(mssql2025.reason.contains("fermo"))
    }

    @Test func staleAspireHashMentionsTheHashInUse() throws {
        let stale = try find(classifyRealCase(), "orbit.apphost-751ef8e8e6-storage-data")

        #expect(stale.reason.contains("hash AppHost vecchio"))
        #expect(stale.reason.contains("48d90b1972"))
    }

    @Test func imageInUseIsMatchedByIdNotByTag() throws {
        // Lo stesso tag di un'immagine in uso, ma un ID diverso: un'immagine sostituita da un pull
        // successivo e rimasta senza container non è "in uso" solo perché ne condivide il nome.
        var snapshot = try DockerFixtures.snapshot()
        snapshot.containers = [container("web", imageId: "sha256:" + String(repeating: "9", count: 64))]

        let mssql2025 = try find(DockerClassifier.classify(snapshot, .empty), "mcr.microsoft.com/mssql/server:2025-latest")

        #expect(mssql2025.verdict != .keep)
    }

    // MARK: - Riferimenti nei progetti

    @Test func imageCitedWithRepositoryAndTagIsKeptAndNamesTheFile() throws {
        let references = self.references(ImageReference(repository: "quay.io/keycloak/keycloak", tag: "26.6", file: "/p/Orbit.AppHost/Program.cs", line: 12))

        let keycloak = try find(classifyRealCase(references), "quay.io/keycloak/keycloak:26.6")

        #expect(keycloak.verdict == .keep)
        #expect(keycloak.ruleId == "referenced")
        #expect(keycloak.reason.contains("/p/Orbit.AppHost/Program.cs:12"))
    }

    @Test func referenceWithoutTagIsOnlyAPossibleReference() throws {
        let references = self.references(ImageReference(repository: "quay.io/keycloak/keycloak", tag: nil, file: "/p/Orbit.AppHost/Program.cs", line: 12))

        let keycloak = try find(classifyRealCase(references), "quay.io/keycloak/keycloak:26.6")

        #expect(keycloak.verdict == .propose)
        #expect(!keycloak.selectedByDefault)
        #expect(keycloak.reason.contains("possibile riferimento"))
        #expect(keycloak.reason.contains("/p/Orbit.AppHost/Program.cs"))
    }

    @Test func referenceWithAnotherTagDoesNotKeepTheImage() throws {
        let references = self.references(ImageReference(repository: "mcr.microsoft.com/mssql/server", tag: "2025-latest", file: "/p/compose.yaml", line: 3))

        let mssql2022 = try find(classifyRealCase(references), "mcr.microsoft.com/mssql/server:2022-latest")

        #expect(mssql2022.verdict == .propose)
    }

    @Test func locallyBuiltWinsOverAProjectReference() throws {
        let references = self.references(ImageReference(repository: "docker.io/library/orbit-api", tag: "dev", file: "/p/compose.yaml", line: 3))

        let local = try find(classifyRealCase(references), "orbit-api:dev")

        #expect(local.verdict == .ask)
    }

    // MARK: - Immagini: casi fuori dal caso reale

    @Test func danglingImageIsSafeToDelete() throws {
        let dangling = try classifyImage(image("sha256:" + String(repeating: "7", count: 64), tags: ["<none>:<none>"]))

        #expect(dangling.verdict == .delete)
        #expect(dangling.ruleId == "dangling")
        #expect(dangling.selectedByDefault)
    }

    @Test func imageLabelledByTestcontainersIsRecreatedByTheTool() throws {
        let built = try classifyImage(image(
            "sha256:" + String(repeating: "8", count: 64),
            tags: ["testcontainers/abcdef:latest"],
            labels: ["org.testcontainers": "true"],
            origin: .built))

        #expect(built.verdict == .delete)
        #expect(built.ruleId == "tool-recreated")
    }

    @Test func withoutIdentityAnImageWithoutDigestsIsLocallyBuilt() throws {
        let classic = try classifyImage(image("sha256:" + String(repeating: "6", count: 64), tags: ["my/app:1"], digests: []))

        #expect(classic.verdict == .ask)
        #expect(classic.ruleId == "locally-built")
    }

    @Test func creationDateIsNotACriterion() throws {
        // alpine:3.20 ha la data zero di Unix (build riproducibile): resta una normale immagine non
        // usata, non "vecchissima, quindi da cancellare".
        let alpine = try find(classifyRealCase(), "alpine:3.20")

        #expect(!alpine.selectedByDefault)
        #expect(!alpine.reason.contains("1970"))
    }

    // MARK: - Volumi

    @Test func composeVolumeOfAnExistingProjectIsKept() throws {
        var snapshot = try DockerFixtures.snapshot(existingComposeProjects: ["shop"])
        snapshot.volumes = [volume("shop_pgdata", compose: "shop")]

        let volume = try #require(DockerClassifier.classify(snapshot, .empty).first { $0.id == "shop_pgdata" })

        #expect(volume.verdict == .keep)
        #expect(volume.ruleId == "compose-project")
    }

    @Test func composeProjectFoundInTheProjectFoldersAlsoKeepsTheVolume() throws {
        var snapshot = try DockerFixtures.snapshot()
        snapshot.volumes = [volume("shop_pgdata", compose: "shop")]
        let references = ProjectReferences(images: [], composeProjects: ["shop"])

        let volume = try #require(DockerClassifier.classify(snapshot, references).first { $0.id == "shop_pgdata" })

        #expect(volume.verdict == .keep)
    }

    @Test func composeVolumeOfAVanishedProjectNeedsExplicitConfirmation() throws {
        var snapshot = try DockerFixtures.snapshot()
        snapshot.volumes = [volume("old_pgdata", compose: "old")]

        let volume = try #require(DockerClassifier.classify(snapshot, .empty).first { $0.id == "old_pgdata" })

        #expect(volume.verdict == .propose)
        #expect(volume.ruleId == "named-unused")
        #expect(!volume.selectedByDefault)
    }

    @Test func aspireVolumeOfAnAppWithNoHashInUseNeedsExplicitConfirmation() throws {
        var snapshot = try DockerFixtures.snapshot()
        snapshot.volumes = [volume("shop.apphost-1234567890-redis-data")]

        let volume = try #require(DockerClassifier.classify(snapshot, .empty).first { $0.id == "shop.apphost-1234567890-redis-data" })

        #expect(volume.ruleId == "named-unused")
    }

    @Test func noVolumeIsEverDeleteNorPreselected() throws {
        for volume in try classifyRealCase() where volume.kind == .volume {
            #expect(volume.verdict != .delete)
            #expect(!volume.selectedByDefault)
        }
    }

    @Test func onlyDeleteVerdictsArePreselected() throws {
        for candidate in try classifyRealCase() {
            #expect(candidate.selectedByDefault == (candidate.verdict == .delete))
        }
    }

    // MARK: - Cache di build

    @Test func buildCacheIsASingleSafeDeletion() throws {
        let caches = try classifyRealCase().filter { $0.kind == .buildCache }
        let cache = try #require(caches.first)

        #expect(caches.count == 1)
        #expect(cache.verdict == .delete)
        #expect(cache.sizeBytes == 106_900_000)
    }

    @Test func buildCacheSharedWithImagesSaysItMayNotBeFreedYet() throws {
        // Misurato: 101,9 MB di cache, 0 B recuperabili — i layer sono condivisi con l'immagine
        // dcptun ancora presente. Presentarla come spazio sicuramente recuperabile sarebbe falso.
        var snapshot = try DockerFixtures.snapshot()
        snapshot.df = DockerDfSummary(entries: [DockerDfEntry(type: DockerDfSummary.buildCacheType, sizeBytes: 101_900_000, reclaimableBytes: 0)])

        let cache = try #require(DockerClassifier.classify(snapshot, .empty).first { $0.kind == .buildCache })

        #expect(cache.reason.contains("condivisa con immagini presenti"))
    }

    @Test func fullyReclaimableBuildCacheHasNoSharingNote() throws {
        let cache = try #require(classifyRealCase().first { $0.kind == .buildCache })

        #expect(!cache.reason.contains("condivisa"))
    }

    @Test func emptyBuildCacheIsNotProposed() throws {
        var snapshot = try DockerFixtures.snapshot()
        snapshot.df = .empty

        #expect(!(try DockerClassifier.classify(snapshot, .empty)).contains { $0.kind == .buildCache })
    }

    // MARK: - Regole

    @Test func rulesAreDeclaredInPriorityOrder() {
        #expect(ImageRules.default.map(\.id) == ["in-use", "dangling", "tool-recreated", "locally-built", "referenced", "superseded", "unused"])
        #expect(VolumeRules.default.map(\.id) == ["mounted", "anonymous", "compose-project", "aspire-current", "aspire-stale", "named-unused"])
    }

    // MARK: - Solo Swift

    // L'eccezione del C# per un elenco personalizzato senza regola finale diventa un errore lanciato.
    @Test func customRulesWithoutAFallbackAreAProgrammingError() throws {
        let snapshot = try DockerFixtures.snapshot()

        #expect(throws: DockerRuleError.self) {
            try DockerClassifier.classify(snapshot, .empty, imageRules: [], volumeRules: VolumeRules.default)
        }
    }

    // Le regex dei nomi di volume seguono .NET: il suo "." accetta "\r" e il suo "$" un "\n" finale.
    @Test func volumeNamePatternsFollowDotNetSemantics() {
        #expect(AspireVolumeName.tryParse("shop.apphost-abcdef-redis-data\n") == AspireVolumeName(app: "shop", hash: "abcdef", resource: "redis"))
        #expect(AspireVolumeName.tryParse("shop\r.apphost-abcdef-redis-data")?.app == "shop\r")
        #expect(AspireVolumeName.tryParse("shop.apphost-abcdef-redis-data\n\n") == nil)
        #expect(AspireVolumeName.tryParse("shop.apphost-ABCDEF-redis-data") == nil)
    }

    // MARK: - Utilità

    private func classifyImage(_ image: DockerImage) throws -> DockerCandidate {
        var snapshot = try DockerFixtures.snapshot()
        snapshot.containers = []
        snapshot.images = [image]
        snapshot.volumes = []
        snapshot.df = .empty

        let candidates = try DockerClassifier.classify(snapshot, .empty)
        #expect(candidates.count == 1)
        return try #require(candidates.first)
    }

    private func references(_ images: ImageReference...) -> ProjectReferences {
        ProjectReferences(images: images, composeProjects: [])
    }

    private func container(_ name: String, imageId: String) -> DockerContainer {
        DockerContainer(id: name, name: name, imageId: imageId, state: "running", exitCode: 0, volumeNames: [], labels: [:])
    }

    private func image(
        _ id: String,
        tags: [String],
        digests: [String] = [],
        labels: [String: String] = [:],
        origin: ImageOrigin = .unknown
    ) -> DockerImage {
        DockerImage(id: id, repoTags: tags, repoDigests: digests, sizeBytes: 1_000, uniqueSizeBytes: nil, labels: labels, origin: origin)
    }

    private func volume(_ name: String, compose: String? = nil) -> DockerVolume {
        DockerVolume(name: name, labels: compose.map { ["com.docker.compose.project": $0] } ?? [:], sizeBytes: 1_000)
    }
}
