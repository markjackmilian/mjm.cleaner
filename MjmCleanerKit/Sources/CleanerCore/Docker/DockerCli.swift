import Foundation

/// Docker non raggiungibile: binario assente, daemon spento, socket chiuso. Il messaggio è già
/// pensato per l'utente — l'interfaccia lo mostra così com'è. Porting di `DockerUnavailableException`.
public struct DockerUnavailableError: Error, Equatable, Sendable, LocalizedError {
    /// Perché Docker non risponde. Solo per «non in esecuzione» ha senso nominare il motore del
    /// contesto su cui si lavora: il motivo non si deduce più dal testo.
    public enum Reason: Sendable, Equatable {
        case notInstalled
        case notRunning
    }

    /// Testo generico: analisi ed esecuzione lo sostituiscono con un testo che nomina il motore del
    /// contesto analizzato, quando lo si riconosce.
    public static var notRunning: String {
        String(localized: "Docker non è in esecuzione. Avvia il motore Docker (Docker Desktop, OrbStack…) e premi Riprova.", bundle: .module)
    }

    public static var notInstalled: String {
        String(localized: "Docker non è installato o non è stato trovato.", bundle: .module)
    }

    public let message: String
    public let reason: Reason

    /// Il motivo predefinito è «non in esecuzione»: solo `DockerCli` lancia «non installato».
    public init(_ message: String, reason: Reason = .notRunning) {
        self.message = message
        self.reason = reason
    }

    public var errorDescription: String? { message }
}

/// Un comando Docker è fallito: il messaggio riporta il testo d'errore della CLI. Porting di
/// `DockerCommandException`.
public struct DockerCommandError: Error, Equatable, Sendable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Porting di `IDockerCli`: l'unico modo in cui il Core parla con Docker.
public protocol DockerCommandRunning: Sendable {
    /// `timeout` nullo: il limite predefinito della CLI (60 secondi).
    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult
}

extension DockerCommandRunning {
    public func run(_ arguments: [String]) async throws -> ProcessResult {
        try await run(arguments, timeout: nil)
    }

    /// Esegue e restituisce lo stdout; qualunque uscita diversa da zero diventa un errore leggibile.
    /// Il timeout si riconosce da `timedOut`, non dal codice di uscita.
    public func runChecked(_ arguments: [String]) async throws -> String {
        let result = try await run(arguments)

        if result.timedOut || result.exitCode != 0 {
            throw DockerCommandError("docker \(arguments.prefix(2).joined(separator: " ")): \(DockerCliErrors.describe(result))")
        }

        return result.standardOutput
    }
}

public enum DockerCliErrors {
    // Messaggi misurati sulle CLI 24–29: il testo cambia fra le versioni, il socket irraggiungibile no.
    private static let daemonUnavailableMarkers = [
        "Cannot connect to the Docker daemon",
        "Is the docker daemon running",
        "error during connect",
        "failed to connect to the docker API",
        "docker.sock: connect:",
    ]

    public static func isDaemonUnavailable(_ standardError: String) -> Bool {
        daemonUnavailableMarkers.contains { DockerText.containsIgnoringCase(standardError, $0) }
    }

    /// La prima riga utile dell'errore della CLI, senza il prefisso ripetuto dal daemon.
    public static func describe(_ result: ProcessResult) -> String {
        if result.timedOut {
            return String(localized: "Docker non ha risposto entro il tempo massimo", bundle: .module)
        }

        let line = DockerText.lines(result.standardError).first
            ?? String(localized: "codice di uscita \(String(result.exitCode))", bundle: .module)

        let prefix = "Error response from daemon: "
        return DockerText.hasPrefix(line, prefix)
            ? String(decoding: line.utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
            : line
    }
}

/// Unico punto dell'applicazione che esegue il binario `docker`, sempre per percorso assoluto
/// (quello trovato da `DockerBinaryLocator`): `posix_spawnp` cerca un nome semplice nel PATH
/// dell'app, che dal Finder è solo `/usr/bin:/bin:/usr/sbin:/sbin`.
public struct DockerCli: DockerCommandRunning {
    private static let defaultTimeout: Duration = .seconds(60)

    private let runner: any ProcessRunning
    private let binaryPath: String?

    public init(runner: any ProcessRunning, binaryPath: String?) {
        self.runner = runner
        self.binaryPath = binaryPath
    }

    public func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
        guard let binaryPath else {
            throw DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled)
        }

        let result: ProcessResult
        do {
            result = try await runner.run(binaryPath, arguments, timeout: timeout ?? Self.defaultTimeout, environment: Self.environment(binaryPath))
        } catch is ProcessLaunchError {
            throw DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled)
        }

        // Il daemon può spegnersi in qualunque momento, anche fra un comando e l'altro di una
        // pulizia: ogni chiamata lo verifica, non solo la prima.
        if result.exitCode != 0 && DockerCliErrors.isDaemonUnavailable(result.standardError) {
            throw DockerUnavailableError(DockerUnavailableError.notRunning)
        }

        return result
    }

    /// Un'app aperta dal Finder riceve un PATH minimo (/usr/bin:/bin:…): la CLI, di Docker Desktop
    /// come di OrbStack, cerca accanto a sé i propri helper (credential helper, plugin), quindi la
    /// sua cartella va in testa.
    private static func environment(_ binary: String) -> [String: String] {
        let directory = PathText.parent(binary) ?? "/usr/local/bin"
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let path = "\(directory):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:\(inherited)"
        return ["PATH": DockerText.trimmedTrailing(path, ":")]
    }
}

public enum DockerBinaryLocator {
    /// Percorsi noti, in ordine: Docker Desktop e OrbStack per l'utente, installazione di sistema,
    /// Homebrew, bundle delle due app. Il binario non sceglie il motore (lo fa il contesto attivo
    /// della CLI): basta che si avvii.
    public static func candidates(homeDirectory: String) -> [String] {
        [
            PathText.join(PathText.join(PathText.join(homeDirectory, ".docker"), "bin"), "docker"),
            PathText.join(PathText.join(PathText.join(homeDirectory, ".orbstack"), "bin"), "docker"),
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
        ]
    }

    /// Il primo candidato che si può eseguire. Disinstallare Docker Desktop può lasciare
    /// `~/.docker/bin/docker` come collegamento orfano: `FileSystem.fileExists` lo darebbe per
    /// presente e l'app direbbe «Docker non è installato» anche con OrbStack acceso.
    public static func find(homeDirectory: String, isExecutable: (String) -> Bool = DockerBinaryLocator.isExecutableFile) -> String? {
        candidates(homeDirectory: homeDirectory).first(where: isExecutable)
    }

    /// Un file regolare eseguibile, raggiunto seguendo i collegamenti (`stat`, non `lstat`).
    public static func isExecutableFile(_ path: String) -> Bool {
        var status = stat()
        guard stat(path, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { return false }
        return access(path, X_OK) == 0
    }
}
