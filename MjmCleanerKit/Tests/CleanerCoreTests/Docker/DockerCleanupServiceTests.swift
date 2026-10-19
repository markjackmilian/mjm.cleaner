import Testing
@testable import CleanerCore

struct DockerCleanupServiceTests {
    private static let rawPath = "/Users/tester/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
    private static let contextCommand = "context inspect --format {{json .}}"

    private struct NoProcess: ProcessRunning {
        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            ProcessResult(exitCode: 0, standardOutput: "16\t" + DockerCleanupServiceTests.rawPath, standardError: "", timedOut: false)
        }
    }

    private func service(_ fs: InMemoryFileSystem, _ cli: FakeDockerCli) -> DockerCleanupService {
        DockerCleanupService(
            collector: DockerInventoryCollector(cli: cli, fileSystem: fs),
            scanner: ProjectReferenceScanner(fileSystem: fs),
            disk: DiskUsageProbe(runner: NoProcess(), fileSystem: fs, diskImagePath: Self.rawPath),
            executor: DockerCleanExecutor(cli: cli, clock: SystemWallClock()),
            contexts: DockerContextReader(cli: cli, homeDirectory: "/Users/tester"))
    }

    @Test func analysisClassifiesWithTheReferencesFoundInTheProjects() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("/Users/tester/projects/orbit/Orbit.AppHost/Program.cs", text: """
            var builder = DistributedApplication.CreateBuilder(args);
            builder.AddKeycloak("keycloak").WithImageTag("26.6");
            """)

        let analysis = try await service(fs, FakeDockerCli.withRealCase()).analyze(["/Users/tester/projects"])

        let keycloak = try #require(analysis.candidates.first { $0.displayName == "quay.io/keycloak/keycloak:26.6" })
        #expect(keycloak.verdict == .keep)
        #expect(keycloak.reason.contains("Program.cs:2"))
    }

    @Test func analysisMeasuresTheDiskImage() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 100)

        let analysis = try await service(fs, FakeDockerCli.withRealCase()).analyze([])

        #expect(analysis.disk.allocatedBytes == Int64(16 * 1024))
        #expect(analysis.disk.apparentBytes == 100)
        #expect(analysis.snapshot.df.images == 5_840_000_000)
    }

    @Test func aDaemonThatDoesNotAnswerNamesTheEngineOfTheActiveContext() async {
        let cli = FakeDockerCli()
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notRunning) }
            .on(Self.contextCommand, #"{"Name":"desktop-linux","Metadata":{"Description":"Docker Desktop"},"Endpoints":{"docker":{"Host":"unix:///Users/tester/.docker/run/docker.sock"}}}"#)

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), cli).analyze([])
        }

        #expect(error == DockerUnavailableError("Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."))
    }

    @Test func anUnreadableContextKeepsTheGenericMessage() async {
        let cli = FakeDockerCli()
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notRunning) }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), cli).analyze([])
        }

        #expect(error == DockerUnavailableError(DockerUnavailableError.notRunning))
        #expect(cli.commandLines.last == Self.contextCommand)
    }

    @Test func aMissingDockerIsNeverRewritten() async {
        let cli = FakeDockerCli()
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled) }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), cli).analyze([])
        }

        #expect(error == DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled))
        #expect(!cli.commandLines.contains { $0.hasPrefix("context") })
    }
}
