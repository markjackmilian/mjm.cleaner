/// Il contesto attivo della CLI, letto con `docker context inspect`, che non contatta il daemon: a
/// daemon spento è l'unico modo di dire quale motore l'utente deve avviare.
public struct DockerContext: Sendable, Equatable {
    public let name: String
    public let description: String
    /// L'endpoint Docker come lo scrive la CLI, per esempio `unix:///Users/x/.orbstack/run/docker.sock`.
    public let host: String

    public init(name: String, description: String, host: String) {
        self.name = name
        self.description = description
        self.host = host
    }

    /// Il motore del contesto: decide la descrizione («Docker Desktop», «OrbStack»), poi l'endpoint,
    /// riconosciuto solo nella forma `unix://` sotto la home. `/var/run/docker.sock` non si risolve:
    /// è un collegamento che l'ultimo motore installato può riscrivere.
    public func engineKind(homeDirectory: String) -> DockerEngineKind {
        let named = DockerEngine.kind(named: description)
        if named != .other { return named }

        let scheme = "unix://"
        guard DockerText.hasPrefix(host, scheme) else { return .other }
        let socket = String(decoding: host.utf8.dropFirst(scheme.utf8.count), as: UTF8.self)
        let home = PathText.trimmingTrailingSlashes(homeDirectory)

        if PathText.isSameOrUnder(socket, home + "/.docker/run") { return .dockerDesktop }
        if PathText.isSameOrUnder(socket, home + "/.orbstack/run") { return .orbStack }
        return .other
    }
}

extension DockerUnavailableError {
    /// Il testo per un daemon che non risponde, con il motore del contesto analizzato quando lo si
    /// riconosce; senza contesto, o con un contesto senza nome, il testo generico.
    public static func notRunningMessage(_ context: DockerContext?, homeDirectory: String) -> String {
        guard let context, !DockerText.isBlank(context.name) else { return notRunning }

        return switch context.engineKind(homeDirectory: homeDirectory) {
        case .dockerDesktop:
            String(localized: "Docker Desktop non è in esecuzione (contesto «\(context.name)»). Avvialo e premi Riprova.", bundle: .module)
        case .orbStack:
            String(localized: "OrbStack non è in esecuzione (contesto «\(context.name)»). Avvialo e premi Riprova.", bundle: .module)
        case .other:
            String(localized: "Il motore Docker del contesto «\(context.name)» non risponde. Avvialo e premi Riprova.", bundle: .module)
        }
    }

    /// Il testo per un daemon che non risponde all'avvio di «Elimina». L'analisi resta valida:
    /// avviato il motore, basta premere di nuovo «Elimina». Il contesto viene dall'analisi, che ne
    /// ha già validato il nome.
    public static func notRunningForDeletionMessage(_ context: DockerContext, homeDirectory: String) -> String {
        return switch context.engineKind(homeDirectory: homeDirectory) {
        case .dockerDesktop:
            String(localized: "Docker Desktop non è in esecuzione (contesto «\(context.name)»). Avvialo e premi di nuovo «Elimina».", bundle: .module)
        case .orbStack:
            String(localized: "OrbStack non è in esecuzione (contesto «\(context.name)»). Avvialo e premi di nuovo «Elimina».", bundle: .module)
        case .other:
            String(localized: "Il motore Docker del contesto «\(context.name)» non risponde. Avvialo e premi di nuovo «Elimina».", bundle: .module)
        }
    }
}

/// Legge il contesto attivo, a cui l'analisi resta fissata, e nomina il motore di un contesto
/// già letto quando il suo daemon non risponde.
public struct DockerContextReader: Sendable {
    private let cli: any DockerCommandRunning
    private let homeDirectory: String

    public init(cli: any DockerCommandRunning, homeDirectory: String) {
        self.cli = cli
        self.homeDirectory = homeDirectory
    }

    /// Lancia: senza un contesto non si può fissare l'analisi. «Non installato» risale com'è.
    public func activeContext() async throws -> DockerContext {
        try DockerJson.parseContext(try await cli.runChecked(["context", "inspect", "--format", "{{json .}}"]))
    }

    /// Il testo per un daemon che non risponde, per il contesto su cui si lavora: non quello attivo
    /// in quel momento, che può essere già un altro.
    public func notRunningMessage(for context: DockerContext) -> String {
        DockerUnavailableError.notRunningMessage(context, homeDirectory: homeDirectory)
    }

    /// Il testo per un daemon che non risponde all'avvio di «Elimina», per il contesto analizzato.
    public func notRunningForDeletionMessage(for context: DockerContext) -> String {
        DockerUnavailableError.notRunningForDeletionMessage(context, homeDirectory: homeDirectory)
    }
}

/// Ogni comando va al daemon del contesto `name`, qualunque sia il contesto attivo. `--context`
/// vale per il singolo comando e non cambia il contesto dell'utente: analisi ed esecuzione restano
/// così sul motore analizzato anche se nel frattempo il contesto attivo cambia (OrbStack lo
/// reimposta quando si avvia).
struct DockerContextCli: DockerCommandRunning {
    private let base: any DockerCommandRunning
    private let name: String

    /// Lancia per un nome fuori dalla forma `[A-Za-z0-9][A-Za-z0-9_.+-]*`: vuoto, con spazi, segni
    /// o lettere non ASCII, oppure che comincia con «-» e verrebbe letto come un'opzione.
    init(_ base: any DockerCommandRunning, context name: String) throws {
        guard name.firstMatch(of: /^[A-Za-z0-9][A-Za-z0-9_.+\-]*$/.matchingSemantics(.unicodeScalar)) != nil else {
            throw DockerOutputError(String(localized: "Nome del contesto Docker non valido: «\(name)».", bundle: .module))
        }
        self.base = base
        self.name = name
    }

    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
        try await base.run(["--context", name] + arguments, timeout: timeout)
    }
}
