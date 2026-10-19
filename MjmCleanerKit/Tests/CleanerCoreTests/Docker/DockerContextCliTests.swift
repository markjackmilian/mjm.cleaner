import Testing
@testable import CleanerCore

/// Solo Swift: ogni comando fissato al contesto letto all'analisi.
struct DockerContextCliTests {
    @Test func everyCommandGoesToTheNamedContext() async throws {
        let base = FakeDockerCli().on("--context desktop-linux volume rm old-data", "old-data")

        let result = try await DockerContextCli(base, context: "desktop-linux").run(["volume", "rm", "old-data"], timeout: .seconds(600))

        #expect(result.exitCode == 0)
        #expect(base.calls == [["--context", "desktop-linux", "volume", "rm", "old-data"]])
    }

    /// `runChecked` nomina il comando che l'analisi ha chiesto, non il prefisso.
    @Test func errorsNameTheCommandNotThePrefix() async throws {
        let base = FakeDockerCli().on("--context orbstack volume inspect x") { FakeDockerCli.fail("Error response from daemon: get x: no such volume") }

        let error = await #expect(throws: DockerCommandError.self) {
            try await DockerContextCli(base, context: "orbstack").runChecked(["volume", "inspect", "x"])
        }

        #expect(error == DockerCommandError("docker volume inspect: get x: no such volume"))
    }

    @Test(arguments: ["default", "desktop-linux", "orbstack", "colima", "rancher-desktop", "lab_2.local+x", "x"])
    func namesDockerAcceptsArePassedAsTheyAre(name: String) async throws {
        let base = FakeDockerCli()

        _ = try await DockerContextCli(base, context: name).run(["info"], timeout: nil)

        #expect(base.calls == [["--context", name, "info"]])
    }

    @Test(arguments: ["", "-H", "--host=tcp://10.0.0.1:2375", "a b", "orbstack\n", "ctx;rm", "_ctx", "dèsktop"])
    func namesDockerRejectsAreRefusedBeforeAnyCommand(name: String) {
        let base = FakeDockerCli()

        #expect(throws: DockerOutputError("Nome del contesto Docker non valido: «\(name)».")) {
            try DockerContextCli(base, context: name)
        }
        #expect(base.calls.isEmpty)
    }

    @Test func aPinnedCollectorReadsItsContextWhateverTheActiveOne() async throws {
        let desktop = FakeDockerCli().on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.0", id: "desktop-id"))
        let orbStack = FakeDockerCli().on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.2", "OrbStack", id: "orbstack-id"))
        let docker = FakeDockerContexts(active: "orbstack", [
            (FakeDockerContexts.desktopLinux, desktop),
            (FakeDockerContexts.orbstack, orbStack),
        ])

        let engine = try await DockerInventoryCollector(cli: docker, fileSystem: InMemoryFileSystem()).pinned(to: "desktop-linux").checkDaemon()

        #expect(engine == DockerEngine(serverVersion: "29.8.0", operatingSystem: "Docker Desktop", id: "desktop-id"))
        #expect(docker.calls == [["--context", "desktop-linux", "info", "--format", DockerInventoryCollector.engineFormat]])
        #expect(orbStack.calls.isEmpty)
    }
}
