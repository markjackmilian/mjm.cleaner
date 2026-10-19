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
            .on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.0"))
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
            .on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.0"))
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
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notRunning) }

        await #expect(throws: DockerUnavailableError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()
        }
        #expect(cli.calls.count == 1)
    }

    @Test(arguments: [
        #"{"ServerVersion":"","OperatingSystem":""}"#,
        #"{"ServerVersion":null,"OperatingSystem":"OrbStack"}"#,
        #"{"OperatingSystem":"Docker Desktop"}"#,
    ])
    func emptyServerVersionMeansTheDaemonIsNotRunning(output: String) async {
        // Senza daemon, "docker info" può comunque stampare la parte client e uscire con 0.
        let cli = FakeDockerCli().on(FakeDockerCli.infoCommand, output)

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()
        }

        #expect(error?.reason == .notRunning)
    }

    @Test func checkDaemonRecognizesTheEngineWithOneInfoCall() async throws {
        let cli = FakeDockerCli().on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.2", "OrbStack"))

        let engine = try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).checkDaemon()

        #expect(engine == DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack"))
        #expect(engine.kind == .orbStack)
        #expect(cli.calls == [["info", "--format", DockerInventoryCollector.engineFormat]])
    }

    @Test func unreadableInfoIsAnOutputError() async {
        let cli = FakeDockerCli().on(FakeDockerCli.infoCommand, "29.8.2")

        await #expect(throws: DockerOutputError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).checkDaemon()
        }
    }

    /// Solo Swift: l'`ID` del daemon arriva con la stessa chiamata `docker info`, nel formato misurato
    /// con OrbStack il 2026-10-19; l'esecutore lo usa per riconoscere un daemon diverso.
    @Test func theDaemonIdComesWithTheSameInfoCall() async throws {
        let cli = FakeDockerCli().on(
            FakeDockerCli.infoCommand,
            #"{"ServerVersion":"29.8.2","OperatingSystem":"OrbStack","ID":"b2756783-e527-49e3-a6c6-cd7f4e49c9ff"}"#)

        let engine = try await DockerInventoryCollector.readEngine(cli)

        #expect(engine == DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack", id: "b2756783-e527-49e3-a6c6-cd7f4e49c9ff"))
        #expect(DockerInventoryCollector.engineFormat
            == #"{"ServerVersion":{{json .ServerVersion}},"OperatingSystem":{{json .OperatingSystem}},"ID":{{json .ID}}}"#)
        #expect(cli.calls == [["info", "--format", DockerInventoryCollector.engineFormat]])
    }

    @Test(arguments: [
        #"{"ServerVersion":"29.8.2","OperatingSystem":"OrbStack"}"#,
        #"{"ServerVersion":"29.8.2","OperatingSystem":"OrbStack","ID":null}"#,
    ])
    func aDaemonWithoutAnIdHasAnEmptyOne(output: String) async throws {
        let cli = FakeDockerCli().on(FakeDockerCli.infoCommand, output)

        let engine = try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).checkDaemon()

        #expect(engine.id == "")
        #expect(engine.kind == .orbStack)
    }
}
