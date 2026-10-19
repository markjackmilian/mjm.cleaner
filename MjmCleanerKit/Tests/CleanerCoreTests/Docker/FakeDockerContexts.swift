import Synchronization
@testable import CleanerCore

/// I contesti della CLI `docker`, ciascuno con il suo motore finto. Come la CLI vera, un comando
/// che comincia con `--context <nome>` va al motore di quel contesto, senza il prefisso; ogni altro
/// va al motore del contesto attivo; `context inspect` risponde con il contesto a cui è rivolto. Il
/// test può cambiare il contesto attivo in qualunque momento, come fa OrbStack quando si avvia.
final class FakeDockerContexts: DockerCommandRunning {
    static let desktopLinux = DockerContext(
        name: "desktop-linux", description: "Docker Desktop", host: "unix:///Users/tester/.docker/run/docker.sock")
    static let orbstack = DockerContext(
        name: "orbstack", description: "OrbStack", host: "unix:///Users/tester/.orbstack/run/docker.sock")

    private struct State {
        var active: String
        var calls: [[String]] = []
    }

    private let engines: [String: (context: DockerContext, cli: FakeDockerCli)]
    private let state: Mutex<State>

    init(active: String, _ contexts: [(context: DockerContext, cli: FakeDockerCli)]) {
        var engines: [String: (context: DockerContext, cli: FakeDockerCli)] = [:]
        for entry in contexts {
            engines[entry.context.name] = entry
        }
        self.engines = engines
        state = Mutex(State(active: active))
    }

    /// Ogni comando così come è arrivato, prefisso compreso.
    var calls: [[String]] { state.withLock { $0.calls } }

    func activate(_ name: String) {
        state.withLock { $0.active = name }
    }

    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
        var name = state.withLock { state in
            state.calls.append(arguments)
            return state.active
        }

        var command = arguments
        if command.first == "--context", let pinned = command.dropFirst().first {
            name = pinned
            command = Array(command.dropFirst(2))
        }

        guard let engine = engines[name] else {
            return FakeDockerCli.fail(#"Failed to initialize: unable to resolve docker endpoint: context "\#(name)": context not found"#)
        }
        if command == ["context", "inspect", "--format", "{{json .}}"] {
            return FakeDockerCli.ok(Self.json(engine.context))
        }
        return try await engine.cli.run(command, timeout: timeout)
    }

    /// La riga di `docker context inspect --format '{{json .}}'`, con i soli campi che il Core legge.
    static func json(_ context: DockerContext) -> String {
        #"{"Name":"\#(context.name)","Metadata":{"Description":"\#(context.description)"},"Endpoints":{"docker":{"Host":"\#(context.host)"}}}"# + "\n"
    }
}
