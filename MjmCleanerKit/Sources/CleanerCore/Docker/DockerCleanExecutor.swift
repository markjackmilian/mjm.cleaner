import Foundation

/// Identificativi stabili delle categorie Docker nello storico.
public enum DockerCategories {
    public static let images = "docker-images"
    public static let volumes = "docker-volumes"
    public static let buildCache = "docker-build-cache"

    /// `DockerCategories.For(kind)` del C#.
    public static func category(for kind: DockerResourceKind) -> String {
        switch kind {
        case .image: images
        case .volume: volumes
        case .buildCache: buildCache
        }
    }
}

/// `after`: `nil` quando la misura finale non è stata possibile (daemon spento a metà).
public struct DockerCleanResult: Sendable, Equatable {
    public let report: CleanReport
    public let before: DockerDfSummary
    public let after: DockerDfSummary?
    public let daemonLost: Bool

    public init(report: CleanReport, before: DockerDfSummary, after: DockerDfSummary?, daemonLost: Bool) {
        self.report = report
        self.before = before
        self.after = after
        self.daemonLost = daemonLost
    }
}

/// Il daemon del contesto analizzato non è più quello dell'analisi: non si è eliminato nulla.
public struct DockerEngineChangedError: Error, Equatable, Sendable, LocalizedError {
    public let message: String

    public init(context: String) {
        message = String(
            localized: "Il motore Docker del contesto «\(context)» non è più quello analizzato: non è stato eliminato nulla. Premi Riprova per analizzarlo di nuovo.",
            bundle: .module)
    }

    public var errorDescription: String? { message }
}

/// Esegue le sole cancellazioni confermate. Ogni garanzia di sicurezza è verificata qui, sul
/// singolo elemento, anche se l'interfaccia l'ha già applicata: la selezione arriva dall'interfaccia
/// e non va fidata, come in `CleanEngine`.
/// - ogni comando va al contesto dell'analisi, e solo se lì risponde ancora lo stesso daemon;
/// - immagini solo per ID completo (`docker rmi sha256:…`), mai per tag;
/// - mai `-f`/`--force`, mai `docker system prune`;
/// - le voci KEEP non arrivano mai a un comando.
///
/// Sequenziale: il daemon serializza comunque le cancellazioni, e un ordine prevedibile rende il
/// resoconto leggibile.
public struct DockerCleanExecutor: Sendable {
    private static let deleteTimeout: Duration = .seconds(600)

    private let cli: any DockerCommandRunning
    private let clock: any WallClock

    public init(cli: any DockerCommandRunning, clock: any WallClock) {
        self.cli = cli
        self.clock = clock
    }

    /// Lancia prima di cancellare qualunque cosa se il nome del contesto non è valido, se lì
    /// risponde un daemon diverso da quello dell'analisi (`DockerEngineChangedError`), se non
    /// risponde nessun daemon (`DockerUnavailableError`) o se la misura iniziale fallisce; poi solo
    /// per un errore fuori contratto della CLI, come il C#. L'annullamento ferma la pulizia fra un
    /// elemento e l'altro e restituisce il resoconto parziale.
    @concurrent
    public func execute(
        _ selected: [DockerCandidate],
        on target: DockerTarget,
        progress: (@Sendable (CleanProgress) -> Void)?
    ) async throws -> DockerCleanResult {
        let startedAt = clock.now
        let start = ContinuousClock.now

        // Ogni comando va al contesto dell'analisi, anche se nel frattempo il contesto attivo è
        // cambiato. Prima di cancellare, lì deve rispondere lo stesso daemon: `default` segue
        // `/var/run/docker.sock`, che il motore avviato per ultimo riscrive.
        let cli = try DockerContextCli(self.cli, context: target.context.name)
        guard try await DockerInventoryCollector.readEngine(cli) == target.engine else {
            throw DockerEngineChangedError(context: target.context.name)
        }

        // Senza la misura iniziale non si può dire quanto si è recuperato: se il daemon non
        // risponde nemmeno a questa, non si è cancellato nulla e l'errore risale all'interfaccia.
        let before = try await DockerInventoryCollector.readDf(cli)

        var deleted: [String] = []
        var errors: [ScanError] = []
        var deletedByCategory: [(category: String, count: Int)] = []
        // Per posizione nella selezione, come il `ReferenceEqualityComparer` del C#: due voci
        // identiche restano due voci.
        var handled = Set<Int>()
        var retry: [(offset: Int, element: DockerCandidate)] = []
        var daemonLost = false

        func countDeleted(_ category: String) {
            if let index = deletedByCategory.firstIndex(where: { $0.category == category }) {
                deletedByCategory[index].count += 1
            } else {
                deletedByCategory.append((category, 1))
            }
        }

        // Un passo per elemento. Restituisce false quando la pulizia va interrotta (daemon sparito o
        // annullamento): l'elemento non viene allora contato come gestito.
        func step(_ entry: (offset: Int, element: DockerCandidate), allowRetry: Bool) async throws -> Bool {
            let candidate = entry.element
            if daemonLost || Task.isCancelled {
                return false
            }

            if let refusal = Self.refusal(candidate) {
                errors.append(ScanError(path: candidate.displayName, kind: .other, message: refusal))
            } else {
                let result: ProcessResult
                do {
                    result = try await Self.shielded(cli, Self.command(candidate))
                } catch let error as DockerUnavailableError {
                    daemonLost = true
                    handled.insert(entry.offset)
                    errors.append(ScanError(path: candidate.displayName, kind: .other, message: error.message))
                    return false
                }

                if result.exitCode == 0 && !result.timedOut {
                    deleted.append(Self.logEntry(candidate))
                    countDeleted(DockerCategories.category(for: candidate.kind))
                } else if allowRetry && Self.hasDependentChildren(result) {
                    // Una base può precedere la propria derivata nell'elenco: si riprova una volta,
                    // dopo che le altre immagini sono state rimosse.
                    retry.append(entry)
                    return true
                } else {
                    errors.append(ScanError(path: candidate.displayName, kind: Self.classify(result), message: DockerCliErrors.describe(result)))
                }
            }

            handled.insert(entry.offset)
            progress?(CleanProgress(currentPath: candidate.displayName, itemsDone: handled.count, itemsTotal: selected.count, bytesFreed: 0))
            return true
        }

        func phase(_ entries: [(offset: Int, element: DockerCandidate)], allowRetry: Bool) async throws -> Bool {
            for entry in entries {
                if !(try await step(entry, allowRetry: allowRetry)) {
                    return false
                }
            }
            return true
        }

        // Fasi: immagini, ritentativi delle immagini con figlie, poi volumi e cache di build
        // (`OrderBy(c => c.Kind)`: ordinamento stabile, prima i volumi).
        let entries = Array(selected.enumerated())
        if try await phase(entries.filter { $0.element.kind == .image }, allowRetry: true),
           try await phase(retry, allowRetry: false) {
            _ = try await phase(
                entries.filter { $0.element.kind == .volume } + entries.filter { $0.element.kind == .buildCache },
                allowRetry: false)
        }

        if daemonLost {
            // L'elemento in corso ha già il suo errore; quelli rimasti non sono stati tentati, e il
            // resoconto deve dirlo invece di lasciarli sparire.
            for entry in entries where !handled.contains(entry.offset) {
                errors.append(ScanError(
                    path: entry.element.displayName,
                    kind: .other,
                    message: String(localized: "non eseguito: \(DockerUnavailableError.notRunning)", bundle: .module)))
            }
        }

        let after = daemonLost ? nil : try await Self.tryReadDf(cli)

        let categories = deletedByCategory.map { entry in
            CategoryCleanResult(
                categoryId: entry.category,
                bytesFreed: after.map { max(0, Self.size(before, entry.category) - Self.size($0, entry.category)) } ?? 0,
                itemsDeleted: entry.count)
        }

        let report = CleanReport(
            startedAt: startedAt,
            duration: ContinuousClock.now - start,
            bytesFreed: categories.reduce(0) { $0 + $1.bytesFreed },
            itemsDeleted: deleted.count,
            itemsFailed: errors.count,
            categories: categories,
            errors: errors,
            deletedPaths: deleted)

        return DockerCleanResult(report: report, before: before, after: after, daemonLost: daemonLost)
    }

    /// Come `CancellationToken.None` nel C#: un comando avviato non viene interrotto dall'annullamento
    /// del chiamante (si fermerebbe a metà una cancellazione che il daemon porta comunque a termine).
    /// Un task non strutturato non eredita l'annullamento del task che ne attende il risultato.
    private static func shielded(_ cli: any DockerCommandRunning, _ arguments: [String]) async throws -> ProcessResult {
        try await Task { try await cli.run(arguments, timeout: deleteTimeout) }.value
    }

    private static func tryReadDf(_ cli: any DockerCommandRunning) async throws -> DockerDfSummary? {
        do {
            return try await Task { try await DockerInventoryCollector.readDf(cli) }.value
        } catch is DockerUnavailableError {
            return nil
        } catch is DockerCommandError {
            return nil
        } catch is DockerOutputError {
            return nil
        }
    }

    private static func refusal(_ candidate: DockerCandidate) -> String? {
        if candidate.verdict == .keep {
            return String(localized: "esito KEEP: non si cancella", bundle: .module)
        }

        // "$" di Swift vale solo alla fine del testo: a differenza di .NET non accetta un "\n"
        // finale, che la regola dichiarata ("sha256:" e 64 cifre esadecimali) comunque esclude.
        switch candidate.kind {
        case .image where candidate.id.firstMatch(of: /^sha256:[0-9a-f]{64}$/.matchingSemantics(.unicodeScalar)) == nil:
            return String(localized: "identificativo non valido: le immagini si cancellano solo per ID completo", bundle: .module)
        // Stessa forma accettata da Docker per i nomi dei volumi: non può iniziare con "-", quindi
        // non può essere scambiato per un'opzione del comando.
        case .volume where candidate.id.firstMatch(of: /^[A-Za-z0-9][A-Za-z0-9_.\-]*$/.matchingSemantics(.unicodeScalar)) == nil:
            return String(localized: "nome di volume non valido", bundle: .module)
        default:
            return nil
        }
    }

    private static func command(_ candidate: DockerCandidate) -> [String] {
        switch candidate.kind {
        case .image: ["rmi", candidate.id]
        case .volume: ["volume", "rm", candidate.id]
        // Qui -f salta solo la domanda interattiva di conferma: senza --all restano le voci della
        // cache ancora referenziate.
        case .buildCache: ["builder", "prune", "-f"]
        }
    }

    private static func logEntry(_ candidate: DockerCandidate) -> String {
        switch candidate.kind {
        case .image: "docker:image:\(candidate.id) (\(candidate.displayName))"
        case .volume: "docker:volume:\(candidate.id)"
        case .buildCache: "docker:build-cache"
        }
    }

    private static func hasDependentChildren(_ result: ProcessResult) -> Bool {
        DockerText.containsIgnoringCase(result.standardError, "dependent child images")
    }

    private static func classify(_ result: ProcessResult) -> ScanErrorKind {
        let text = result.standardError
        if DockerText.containsIgnoringCase(text, "No such") {
            return .notFound
        }

        return DockerText.containsIgnoringCase(text, "in use") || DockerText.containsIgnoringCase(text, "being used") ? .inUse : .other
    }

    private static func size(_ df: DockerDfSummary, _ category: String) -> Int64 {
        switch category {
        case DockerCategories.images: df.images
        case DockerCategories.volumes: df.volumes
        default: df.buildCache
        }
    }
}
