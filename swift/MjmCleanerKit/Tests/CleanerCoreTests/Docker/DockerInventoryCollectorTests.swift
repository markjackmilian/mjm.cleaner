import Testing
@testable import CleanerCore

struct DockerInventoryCollectorTests {
    @Test func collectsTheWholeInventoryFromJsonOutput() async throws {
        let snapshot = try await DockerInventoryCollector(cli: FakeDockerCli.withRealCase(), fileSystem: InMemoryFileSystem()).collect()

        #expect(snapshot.containers.count == 2)
        #expect(snapshot.images.count == 10)
        #expect(snapshot.volumes.count == 6)
        #expect(snapshot.images.first { $0.id == DockerFixtures.dcptunId }?.uniqueSizeBytes == 76_740_000)
        #expect(snapshot.volumes.first { $0.name == "orbit.apphost-48d90b1972-sql-data" }?.sizeBytes == 158_300_000)
        #expect(snapshot.df.buildCache == 106_900_000)
    }

    @Test func inspectsAllImagesInOneCallById() async throws {
        let cli = try FakeDockerCli.withRealCase()

        _ = try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()

        let inspects = cli.calls.filter { $0.first == "image" }
        let inspect = try #require(inspects.first)
        #expect(inspects.count == 1)
        #expect(inspect.count == 12)
        #expect(inspect.dropFirst(2).allSatisfy { $0.hasPrefix("sha256:") })
    }

    @Test func onlyReadOnlyCommandsAreUsed() async throws {
        let cli = try FakeDockerCli.withRealCase()

        _ = try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()

        let readOnly = ["info", "ps", "container inspect", "images", "image inspect", "volume ls", "volume inspect", "system df"]
        for line in cli.commandLines {
            #expect(readOnly.contains { line.hasPrefix($0) })
        }
    }

    @Test func emptyListsAreNotInspected() async throws {
        let cli = FakeDockerCli()
            .on("info --format {{json .ServerVersion}}", "\"29.8.0\"")
            .on("ps -aq --no-trunc", "")
            .on("images --no-trunc --format {{json .}}", "")
            .on("volume ls --format {{json .}}", "")
            .on("system df -v --format {{json .}}", #"{"Images":[],"Containers":[],"Volumes":[],"BuildCache":[]}"#)
            .on("system df --format {{json .}}", "")

        let snapshot = try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()

        #expect(snapshot.images.isEmpty)
        #expect(!cli.commandLines.contains { $0.contains("inspect") })
    }

    @Test func composeProjectExistsWhenItsWorkingDirectoryIsStillOnDisk() async throws {
        let containers = """
            [{"Id":"1","Name":"/shop-db-1","Image":"sha256:1","State":{"Status":"exited","ExitCode":0},"Mounts":[],
              "Config":{"Labels":{"com.docker.compose.project":"shop","com.docker.compose.project.working_dir":"/Users/tester/projects/shop"}}},
             {"Id":"2","Name":"/old-db-1","Image":"sha256:1","State":{"Status":"exited","ExitCode":0},"Mounts":[],
              "Config":{"Labels":{"com.docker.compose.project":"old","com.docker.compose.project.working_dir":"/Users/tester/projects/old"}}}]
            """
        let cli = FakeDockerCli()
            .on("info --format {{json .ServerVersion}}", "\"29.8.0\"")
            .on("ps -aq --no-trunc", "1\n2\n")
            .on("container inspect 1 2", containers)
            .on("images --no-trunc --format {{json .}}", "")
            .on("volume ls --format {{json .}}", "")
            .on("system df -v --format {{json .}}", "{}")
            .on("system df --format {{json .}}", "")
        let fs = InMemoryFileSystem()
        fs.addDirectory("/Users/tester/projects/shop")

        let snapshot = try await DockerInventoryCollector(cli: cli, fileSystem: fs).collect()

        #expect(snapshot.existingComposeProjects == ["shop"])
    }

    @Test func daemonThatDoesNotAnswerStopsTheCollection() async {
        let cli = FakeDockerCli()
            .on("info --format {{json .ServerVersion}}") { throw DockerUnavailableError(DockerUnavailableError.notRunning) }

        await #expect(throws: DockerUnavailableError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()
        }
        #expect(cli.calls.count == 1)
    }

    @Test func emptyServerVersionMeansTheDaemonIsNotRunning() async {
        // Senza daemon, "docker info" può comunque stampare la parte client e uscire con 0.
        let cli = FakeDockerCli().on("info --format {{json .ServerVersion}}", "\"\"")

        await #expect(throws: DockerUnavailableError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()
        }
    }
}
