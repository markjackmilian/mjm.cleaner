import Foundation

/// Come si può installare l'aggiornamento verificato.
public enum InstallMode: Sendable, Equatable {
    /// «Installa e riavvia»: lo script sostituisce il bundle sul posto.
    case inPlace
    /// «Mostra nel Finder»: il bundle va sostituito a mano, per il motivo indicato.
    case manual(reason: String)
}

/// L'esito dell'ultima installazione, scritto dallo script in `install-result`.
public enum InstallOutcome: Sendable, Equatable {
    case succeeded(AppVersion)
    /// Il passo dello script che non è riuscito (`copy`, `move-old`, `move-new`, `rollback`, `wait`).
    case failed(step: String)
}

/// Avvia un processo senza attenderlo: deve sopravvivere alla chiusura dell'app.
public protocol DetachedLaunching: Sendable {
    func launch(_ executable: String, _ arguments: [String], environment: [String: String]) throws
}

/// `Process` con input e output su `/dev/null`: alla chiusura dell'app il figlio passa a launchd e
/// continua; lo script ignora anche SIGHUP.
public struct DetachedProcessLauncher: DetachedLaunching {
    public init() {}

    public func launch(_ executable: String, _ arguments: [String], environment: [String: String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

/// Prerequisiti, avvio dello script di sostituzione (`Resources/update-install.sh`) ed esito.
public struct UpdateInstaller: Sendable {
    static let resultFileName = "install-result"
    /// Passi da 0,2 s con cui lo script attende la fine dell'app: 30 secondi.
    static let waitSteps = 150
    /// Il PATH dello script: solo i comandi di sistema, mai quelli dell'ambiente dell'utente.
    static let scriptEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

    private let context: UpdateContext
    private let updatesDirectory: String
    private let launcher: any DetachedLaunching

    public init(context: UpdateContext, updatesDirectory: String, launcher: any DetachedLaunching) {
        self.context = context
        self.updatesDirectory = updatesDirectory
        self.launcher = launcher
    }

    public func mode() -> InstallMode {
        let bundle = context.bundlePath
        guard bundle.hasSuffix(".app"), let parent = PathText.parent(bundle) else {
            return .manual(reason: String(localized: "l'app non gira da un bundle .app", bundle: .module))
        }
        if bundle.contains("/AppTranslocation/") {
            return .manual(reason: String(
                localized: "macOS esegue l'app da una posizione temporanea (App Translocation): spostala nella cartella Applicazioni",
                bundle: .module))
        }
        guard FileManager.default.isWritableFile(atPath: parent) else {
            return .manual(reason: String(localized: "la cartella \(parent) non è scrivibile", bundle: .module))
        }
        return .inPlace
    }

    /// Copia lo script in una cartella temporanea propria e lo avvia staccato; poi l'app deve
    /// chiudersi entro 30 secondi.
    public func launch(_ update: VerifiedUpdate) throws {
        if case .manual(let reason) = mode() { throw UpdateError.installFailed(reason) }
        guard let source = Bundle.module.url(forResource: "update-install", withExtension: "sh") else {
            throw UpdateError.installFailed(String(localized: "script di installazione mancante", bundle: .module))
        }
        let manager = FileManager.default
        let directory = try manager.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: updatesDirectory, isDirectory: true), create: true)
        let script = directory.appendingPathComponent("update-install.sh")
        try manager.copyItem(at: source, to: script)

        // Un esito vecchio non deve passare per quello di questa installazione.
        try? manager.removeItem(atPath: PathText.join(updatesDirectory, Self.resultFileName))
        try launcher.launch("/bin/sh", [
            script.path(percentEncoded: false),
            String(context.processIdentifier),
            context.bundlePath,
            update.bundlePath,
            update.release.tag,
            updatesDirectory,
            String(Self.waitSteps),
        ], environment: Self.scriptEnvironment)
    }

    /// L'esito lasciato dall'ultima installazione, letto una volta sola: il file si cancella.
    public func takeOutcome() -> InstallOutcome? {
        let path = PathText.join(updatesDirectory, Self.resultFileName)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        try? FileManager.default.removeItem(atPath: path)
        let words = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count == 2 else { return nil }
        switch words[0] {
        case "ok": return AppVersion(words[1]).map(InstallOutcome.succeeded)
        case "failed": return .failed(step: words[1])
        default: return nil
        }
    }
}
