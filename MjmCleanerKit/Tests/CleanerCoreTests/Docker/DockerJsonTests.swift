import Testing
@testable import CleanerCore

struct DockerJsonTests {
    @Test func containersKeepFullImageIdStateAndOnlyNamedVolumeMounts() throws {
        let containers = try DockerJson.parseContainers(DockerFixtures.read("containers.json"))

        let storage = try #require(containers.first { $0.name == "storage-bedaxjvn" })
        #expect(containers.filter { $0.name == "storage-bedaxjvn" }.count == 1)
        #expect(storage.imageId == DockerFixtures.azuriteId)
        #expect(storage.state == "exited")
        #expect(storage.exitCode == 137)
        #expect(storage.volumeNames == ["orbit.apphost-48d90b1972-storage-data"])
        #expect(storage.labels["com.microsoft.developer.usvc-dev.name"] == "storage-bedaxjvn")
    }

    @Test func imagesReadTagsDigestsSizeLabelsAndOrigin() throws {
        let images = try DockerJson.parseImages(
            DockerFixtures.read("images.json"),
            uniqueSizes: [DockerFixtures.dcptunId: 76_740_000])

        let dcptun = try #require(images.first { $0.id == DockerFixtures.dcptunId })
        #expect(dcptun.repoTags == ["dcptun_developer_ms:0.25.13"])
        #expect(dcptun.repoDigests.count == 1)
        #expect(dcptun.sizeBytes == 195_234_351)
        #expect(dcptun.uniqueSizeBytes == 76_740_000)
        #expect(dcptun.origin == .built)
        #expect(dcptun.labels["com.microsoft.developer.usvc-dev.base-image-digest"] == DockerFixtures.azureLinuxId)

        let mssql = try #require(images.first { $0.id == DockerFixtures.mssql2025Id })
        #expect(mssql.origin == .pulled)
        #expect(mssql.uniqueSizeBytes == nil)
    }

    @Test func missingLabelsAndIdentityAreTolerated() throws {
        let json = """
            [{"Id":"sha256:1","RepoTags":null,"RepoDigests":[],"Size":10,"Config":null},
             {"Id":"sha256:2","RepoTags":["a:1"],"RepoDigests":null,"Size":20,"Config":{"Labels":null}}]
            """

        let images = try DockerJson.parseImages(json)

        #expect(images.allSatisfy { $0.labels.isEmpty })
        #expect(images.allSatisfy { $0.origin == .unknown })
        let first = try #require(images.first)
        let second = try #require(images.last)
        #expect(images.count == 2)
        #expect(first.repoTags.isEmpty)
        #expect(first.isDangling)
        #expect(second.repoDigests.isEmpty)
    }

    @Test func identityWithBothBuildAndPullCountsAsPulled() throws {
        let json = """
            [{"Id":"sha256:1","RepoTags":["a:1"],"Size":1,"Identity":{"Build":[{"Ref":"x"}],"Pull":[{"Repository":"a"}]}}]
            """

        #expect(try DockerJson.parseImages(json).first?.origin == .pulled)
    }

    @Test func volumesTakeLabelsFromInspectAndSizeFromSystemDf() throws {
        let verbose = try DockerJson.parseDfVerbose(DockerFixtures.read("df-verbose.json"))
        let volumes = try DockerJson.parseVolumes(DockerFixtures.read("volumes.json"), sizes: verbose.volumeSizes)

        let sql = try #require(volumes.first { $0.name == "orbit.apphost-48d90b1972-sql-data" })
        #expect(sql.sizeBytes == 158_300_000)
        #expect(sql.labels.isEmpty)
        let anonymous = try #require(volumes.first { $0.name == DockerFixtures.anonymousVolume })
        #expect(anonymous.sizeBytes == nil)
    }

    @Test func dfVerboseReadsUniqueImageSizes() throws {
        let verbose = try DockerJson.parseDfVerbose(DockerFixtures.read("df-verbose.json"))

        #expect(verbose.imageUniqueSizes[DockerFixtures.azureLinuxId] == 1_131)
    }

    @Test func dfSummaryReadsOneEntryPerType() throws {
        let df = try DockerJson.parseDfSummary(DockerFixtures.read("df.jsonl"))

        #expect(df.images == 5_840_000_000)
        #expect(df.volumes == 558_500_000)
        #expect(df.buildCache == 106_900_000)
        let cache = df.entries.filter { $0.type == DockerDfSummary.buildCacheType }
        #expect(cache.count == 1)
        #expect(cache.first?.reclaimableBytes == 106_900_000)
    }

    @Test func jsonLinesPropertyIgnoresBlankLines() throws {
        let lines = """
            {"ID":"sha256:1","Repository":"a"}

            {"ID":"sha256:2","Repository":"b"}
            """

        #expect(try DockerJson.parseJsonLinesProperty(lines, "ID") == ["sha256:1", "sha256:2"])
    }

    // Solo Swift: dove .NET lanciava un'eccezione diversa da DockerOutputException (`GetInt64` o
    // `GetInt32` su un numero non intero o fuori intervallo, `TryGetProperty` su un elemento che non
    // è un oggetto) il campo vale come assente, come quando manca.
    @Test func pathologicalFieldsAreReadAsAbsent() throws {
        let images = try DockerJson.parseImages(#"[{"Id":"sha256:1","Size":1.5},{"Id":"sha256:2","Size":true},"x"]"#)
        #expect(images.map(\.sizeBytes) == [0, 0, 0])
        #expect(images.map(\.id) == ["sha256:1", "sha256:2", ""])

        let containers = try DockerJson.parseContainers(#"[{"Id":"1","State":{"ExitCode":4294967296}},{"Id":"2","State":"exited"}]"#)
        #expect(containers.map(\.exitCode) == [0, 0])
    }

    @Test func invalidJsonBecomesAReadableError() {
        let error = #expect(throws: DockerOutputError.self) {
            try DockerJson.parseContainers("Error response from daemon")
        }

        #expect(error?.message.lowercased().contains("container") == true)
    }
}
