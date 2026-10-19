import Synchronization
@testable import CleanerCore

/// CLI finta: risponde con le fixture per comando (argomenti uniti da spazi) e registra ogni
/// invocazione, così i test possono verificare COSA verrebbe eseguito su un Docker vero.
///
/// Diversamente dal doppio C#, che ignorava il `CancellationToken`, rifiuta di avviare un comando da
/// un task annullato, come `ProcessRunner`: così i test verificano anche che l'esecutore isoli
/// dall'annullamento i comandi che il C# lanciava con `CancellationToken.None`.
final class FakeDockerCli: DockerCommandRunning {
    typealias Respond = @Sendable ([String]) throws -> ProcessResult

    private struct State {
        var responses: [String: Respond] = [:]
        var prefixResponses: [(prefix: String, respond: Respond)] = []
        var calls: [[String]] = []
    }

    private let state = Mutex(State())

    var calls: [[String]] { state.withLock { $0.calls } }

    var commandLines: [String] { calls.map { $0.joined(separator: " ") } }

    @discardableResult
    func on(_ commandLine: String, _ standardOutput: String) -> FakeDockerCli {
        on(commandLine) { Self.ok(standardOutput) }
    }

    @discardableResult
    func on(_ commandLine: String, respond: @escaping @Sendable () throws -> ProcessResult) -> FakeDockerCli {
        state.withLock { $0.responses[commandLine] = { _ in try respond() } }
        return self
    }

    @discardableResult
    func onPrefix(_ prefix: String, respond: @escaping Respond) -> FakeDockerCli {
        state.withLock { $0.prefixResponses.append((prefix, respond)) }
        return self
    }

    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
        try Task.checkCancellation()
        let line = arguments.joined(separator: " ")

        let respond: Respond? = state.withLock { state in
            state.calls.append(arguments)
            if let exact = state.responses[line] {
                return exact
            }
            // L'ultima registrata vince: un test può restringere una risposta generica ("rmi ") a un
            // caso specifico ("rmi sha256:d4…") aggiungendola dopo.
            return state.prefixResponses.last { DockerText.hasPrefix(line, $0.prefix) }?.respond
        }

        guard let respond else {
            return ProcessResult(exitCode: 1, standardOutput: "", standardError: "comando non previsto dal test: \(line)", timedOut: false)
        }
        return try respond(arguments)
    }

    static func ok(_ standardOutput: String = "") -> ProcessResult {
        ProcessResult(exitCode: 0, standardOutput: standardOutput, standardError: "", timedOut: false)
    }

    static func fail(_ standardError: String) -> ProcessResult {
        ProcessResult(exitCode: 1, standardOutput: "", standardError: standardError, timedOut: false)
    }

    /// La riga di `docker info` con cui `DockerInventoryCollector.checkDaemon` riconosce il motore.
    static let infoCommand = "info --format " + DockerInventoryCollector.engineFormat

    /// La risposta di `docker info` di un daemon `version` che si presenta come `operatingSystem`;
    /// con `id`, anche l'`ID` del daemon.
    static func info(_ version: String, _ operatingSystem: String = "Docker Desktop", id: String? = nil) -> String {
        let idField = id.map { #","ID":"\#($0)""# } ?? ""
        return #"{"ServerVersion":"\#(version)","OperatingSystem":"\#(operatingSystem)"\#(idField)}"# + "\n"
    }

    /// Una CLI che risponde con l'intero caso reale delle fixture.
    static func withRealCase() throws -> FakeDockerCli {
        let json = "{{json .}}"
        let images = try DockerJson.parseImages(DockerFixtures.read("images.json"))
            .map { #"{"ID":"\#($0.id)","Repository":"x","Tag":"y"}"# }
            .joined(separator: "\n")
        let volumes = try DockerJson.parseVolumes(DockerFixtures.read("volumes.json"))
            .map { #"{"Name":"\#($0.name)","Driver":"local"}"# }
            .joined(separator: "\n")
        let containerIds = try DockerJson.parseContainers(DockerFixtures.read("containers.json")).map(\.id)
        let containersJson = try DockerFixtures.read("containers.json")
        let imagesJson = try DockerFixtures.read("images.json")
        let volumesJson = try DockerFixtures.read("volumes.json")

        return FakeDockerCli()
            .on(infoCommand, info("29.8.0"))
            .on("ps -aq --no-trunc", containerIds.joined(separator: "\n") + "\n")
            .onPrefix("container inspect ") { _ in ok(containersJson) }
            .on("images --no-trunc --format \(json)", images)
            .onPrefix("image inspect ") { _ in ok(imagesJson) }
            .on("volume ls --format \(json)", volumes)
            .onPrefix("volume inspect ") { _ in ok(volumesJson) }
            .on("system df -v --format \(json)", try DockerFixtures.read("df-verbose.json"))
            .on("system df --format \(json)", try DockerFixtures.read("df.jsonl"))
    }
}

/// Un valore condiviso fra il test e i callback `@Sendable` della CLI finta: l'equivalente delle
/// variabili locali catturate dalle lambda C# (`int dfCalls = 0; … dfCalls++`).
final class Shared<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    init(_ value: Value) {
        storage = Mutex(value)
    }

    var value: Value { storage.withLock { $0 } }

    func set(_ value: Value) {
        storage.withLock { $0 = value }
    }
}

extension Shared where Value == Int {
    /// `++counter` del C#: incrementa e restituisce il nuovo valore.
    func increment() -> Int {
        storage.withLock { value in
            value += 1
            return value
        }
    }
}
