import Synchronization
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

    /// Un nome non valido ferma il collettore fissato: niente ripiego sul contesto attivo.
    @Test func pinnedRefusesAnInvalidNameInsteadOfFallingBackToTheActiveContext() {
        let collector = DockerInventoryCollector(cli: FakeDockerCli(), fileSystem: InMemoryFileSystem())

        #expect(throws: DockerOutputError("Nome del contesto Docker non valido: «-H».")) {
            try collector.pinned(to: "-H")
        }
    }

    /// Il decoratore inoltra il timeout del chiamante: l'esecutore cancella con 600 secondi, non con
    /// il limite predefinito della CLI.
    @Test func decoratorForwardsTheCallersTimeout() async throws {
        let spy = TimeoutSpy()

        _ = try await DockerContextCli(spy, context: "orbstack").run(["volume", "rm", "x"], timeout: .seconds(600))
        _ = try await DockerContextCli(spy, context: "orbstack").run(["info"], timeout: nil)

        #expect(spy.timeouts == [.seconds(600), nil])
    }
}

/// Registra il timeout di ogni comando.
private final class TimeoutSpy: DockerCommandRunning {
    private let seen = Mutex<[Duration?]>([])

    var timeouts: [Duration?] { seen.withLock { $0 } }

    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
        seen.withLock { $0.append(timeout) }
        return FakeDockerCli.ok()
    }
}
