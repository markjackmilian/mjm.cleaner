import Darwin
import Foundation

public protocol CleanPerforming: Sendable {
    func clean(
        _ selections: [CategorySelection],
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> CleanReport
}

/// Eliminazione definitiva. Sequenziale: su un singolo volume il parallelismo non accelera e
/// renderebbe il resoconto meno prevedibile. Non lancia mai: l'annullamento restituisce un
/// resoconto parziale, perché ciò che è già stato eliminato deve finire comunque nello storico.
public struct CleanEngine: CleanPerforming {
    private let fileSystem: any FileSystem
    private let pathGuard: any PathGuarding
    private let clock: any WallClock

    public init(fileSystem: any FileSystem, pathGuard: any PathGuarding, clock: any WallClock) {
        self.fileSystem = fileSystem
        self.pathGuard = pathGuard
        self.clock = clock
    }

    @concurrent
    public func clean(
        _ selections: [CategorySelection],
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> CleanReport {
        let startedAt = clock.now
        let start = ContinuousClock.now

        var categories: [CategoryCleanResult] = []
        var errors: [ScanError] = []
        var deleted: [String] = []
        var totalBytes: Int64 = 0
        var totalDeleted = 0
        var totalFailed = 0
        var done = 0
        let total = selections.reduce(0) { $0 + $1.items.count }
        var lastSeenPath = ""

        // Due selezioni con lo stesso identificativo confluiscono in un'unica voce del resoconto.
        func addToCategory(_ categoryId: String, bytes: Int64, items: Int) {
            if let index = categories.firstIndex(where: { $0.categoryId == categoryId }) {
                let existing = categories[index]
                categories[index] = CategoryCleanResult(
                    categoryId: categoryId,
                    bytesFreed: existing.bytesFreed + bytes,
                    itemsDeleted: existing.itemsDeleted + items)
            } else {
                categories.append(CategoryCleanResult(categoryId: categoryId, bytesFreed: bytes, itemsDeleted: items))
            }
        }

        func fail(_ error: ScanError, _ path: String) {
            errors.append(error)
            totalFailed += 1
            progress?(CleanProgress(currentPath: path, itemsDone: done, itemsTotal: total, bytesFreed: totalBytes))
        }

        // Un errore fuori contratto (non un FileSystemError) non deve far perdere il resoconto:
        // per un'app che cancella senza Cestino, l'elenco di ciò che è già stato eliminato è
        // l'unica ricostruzione possibile. Meglio un resoconto con un errore ignoto che nessuno.
        do {
            // Ultima linea di difesa: ogni root distinta va validata con validateRoot, una volta
            // sola, PRIMA dei singoli elementi. validate da solo presuppone una root già validata
            // e, quando la root è il genitore diretto dell'elemento (ogni regola clearContents),
            // non vedrebbe un collegamento sulla root stessa. L'elenco arriva dall'interfaccia dopo
            // la conferma (manipolabile) e può essere scaduto (root sostituita da un collegamento
            // fra scansione e conferma): richiamare validateRoot qui copre entrambi i casi.
            // Chiave: i byte UTF-8 del percorso ripiegato (OrdinalIgnoreCase). Una chiave String
            // unirebbe percorsi canonicamente equivalenti che .NET distingue (U+212A e "K", NFC e
            // NFD): una root erediterebbe il verdetto di un'altra senza essere mai validata.
            var rootVerdicts: [[UInt8]: GuardVerdict] = [:]
            for item in selections.flatMap(\.items) {
                let key = Self.rootKey(item.declaredRoot)
                if rootVerdicts[key] == nil {
                    rootVerdicts[key] = pathGuard.validateRoot(item.declaredRoot)
                }
            }

            categoryLoop: for selection in selections {
                // Una categoria non ancora iniziata non entra nel resoconto, nemmeno a zero.
                if Task.isCancelled { break categoryLoop }

                if !categories.contains(where: { $0.categoryId == selection.categoryId }) {
                    categories.append(CategoryCleanResult(categoryId: selection.categoryId, bytesFreed: 0, itemsDeleted: 0))
                }

                for item in selection.items {
                    if Task.isCancelled { break categoryLoop }

                    done += 1
                    lastSeenPath = item.path

                    // Root negata: fallisce solo QUESTO elemento, non l'intera pulizia. In Swift una
                    // root nulla è impossibile per tipo; una root vuota viene negata da validateRoot.
                    let rootEntry = rootVerdicts[Self.rootKey(item.declaredRoot)]
                    guard let rootVerdict = rootEntry, rootVerdict.isAllowed else {
                        let reason = rootEntry?.reason
                            ?? String(localized: "root dichiarata non riconosciuta", bundle: .module)
                        fail(ScanError(path: item.path, kind: .other, message: reason), item.path)
                        continue
                    }

                    // Lo scanner enumera dalla root DICHIARATA, mentre validateRoot può averla
                    // risolta a una stringa diversa ($TMPDIR: "/var" → "/private/var"). L'elemento
                    // va riportato nel sistema di riferimento RISOLTO PRIMA di validarlo: prima si
                    // riscrive, poi si valida, poi si cancella il percorso che il guard restituisce.
                    let resolvedRoot = rootVerdict.canonicalPathValidated
                    let rewrittenPath = Self.rewriteToResolvedRoot(item.path, declaredRoot: item.declaredRoot, resolvedRoot: resolvedRoot)

                    let verdict = pathGuard.validate(rewrittenPath, declaredRoot: resolvedRoot)
                    guard verdict.isAllowed else {
                        fail(ScanError(path: item.path, kind: .other, message: verdict.reason), item.path)
                        continue
                    }

                    // Si elimina il percorso che il guard ha VALIDATO, non quello di partenza.
                    let target = verdict.canonicalPathValidated

                    do {
                        // Si contano solo i byte davvero liberati, rimisurati subito prima.
                        let size = try measureRealSize(target, isDirectory: item.isDirectory)

                        if item.isDirectory {
                            try fileSystem.deleteDirectoryRecursively(target)
                        } else {
                            // File.Exists di .NET: falso anche per un collegamento a una cartella
                            // (vedi registro di parità, candidati a miglioramento).
                            guard fileSystem.fileExists(target) else {
                                throw FileSystemError(code: ENOENT, path: target)
                            }
                            try fileSystem.deleteFile(target)
                        }

                        totalBytes += size
                        totalDeleted += 1
                        deleted.append(target)
                        journal?.recordDeleted(target)
                        addToCategory(selection.categoryId, bytes: size, items: 1)

                        if item.pruneEmptyDirectories {
                            do {
                                for directory in try pruneEmptyParents(of: target, resolvedRoot: resolvedRoot) {
                                    deleted.append(directory)
                                    journal?.recordDeleted(directory)
                                }
                            } catch let error as FileSystemError {
                                errors.append(RuleScanner.describe(error.path, error))
                                totalFailed += 1
                            }
                        }
                    } catch let error as FileSystemError {
                        errors.append(RuleScanner.describe(item.path, error))
                        totalFailed += 1
                    }

                    progress?(CleanProgress(currentPath: item.path, itemsDone: done, itemsTotal: total, bytesFreed: totalBytes))
                }
            }
        } catch {
            errors.append(ScanError(path: lastSeenPath, kind: .other, message: String(describing: error)))
            totalFailed += 1
        }

        return CleanReport(
            startedAt: startedAt,
            duration: ContinuousClock.now - start,
            bytesFreed: totalBytes,
            itemsDeleted: totalDeleted,
            itemsFailed: totalFailed,
            categories: categories,
            errors: errors,
            deletedPaths: deleted)
    }

    /// Risale dal genitore dell'elemento selezionato fino alla root (esclusa). La rimozione POSIX
    /// è atomica: se nel frattempo compare un contenuto, `ENOTEMPTY` ferma la risalita senza
    /// cancellare nulla. Le directory non toccate da un elemento selezionato non vengono visitate.
    private func pruneEmptyParents(of deletedPath: String, resolvedRoot: String) throws -> [String] {
        var removed: [String] = []
        var candidate = PathText.parent(deletedPath)

        while let directory = candidate {
            if PathText.equalsIgnoringCase(directory, resolvedRoot) { break }

            let verdict = pathGuard.validate(directory, declaredRoot: resolvedRoot)
            guard verdict.isAllowed else { break }
            let validated = verdict.canonicalPathValidated
            if PathText.equalsIgnoringCase(validated, resolvedRoot) { break }

            do {
                try fileSystem.deleteDirectoryIfEmpty(validated)
                removed.append(validated)
            } catch let error as FileSystemError where error.code == ENOTEMPTY {
                break
            } catch let error as FileSystemError where error.code == ENOENT {
                // Può essere stata rimossa da un'operazione precedente: la directory superiore
                // potrebbe essere diventata vuota a sua volta.
            }

            candidate = PathText.parent(directory)
        }

        return removed
    }

    /// Chiave di confronto per le root: la forma ripiegata in byte UTF-8, non una `String`, perché
    /// `String` confronta per equivalenza canonica.
    private static func rootKey(_ root: String) -> [UInt8] {
        Array(PathText.folded(root).utf8)
    }

    /// Riporta `path` dal sistema di riferimento della root DICHIARATA a quello della sua
    /// risoluzione. Se `path` non comincia con la root dichiarata (confine di segmento, senza
    /// distinzione fra maiuscole e minuscole) non c'è nulla da riscrivere: validate lo rileverà.
    static func rewriteToResolvedRoot(_ path: String, declaredRoot: String, resolvedRoot: String) -> String {
        if PathText.equalsIgnoringCase(declaredRoot, resolvedRoot) { return path }
        if PathText.equalsIgnoringCase(path, declaredRoot) { return resolvedRoot }
        if PathText.hasPrefixIgnoringCase(path, declaredRoot + "/") {
            // Il prefisso è riconosciuto senza distinzione fra maiuscole e minuscole, scalare per
            // scalare: si taglia per scalari (il ripiegamento non cambia mai il loro numero), non per
            // Character né per byte (due forme di una lettera possono avere lunghezze UTF-8 diverse).
            var rest = String.UnicodeScalarView()
            rest.append(contentsOf: path.unicodeScalars.dropFirst(declaredRoot.unicodeScalars.count))
            return resolvedRoot + String(rest)
        }
        return path
    }

    /// Dimensione reale letta subito prima di cancellare, mai quella dichiarata dall'interfaccia.
    /// Se la lettura fallisce con un `FileSystemError` vale zero: il tentativo di cancellazione che
    /// segue registrerà l'errore con la classificazione corretta. Gli errori fuori da quel contratto
    /// si propagano fino al catch esterno del motore (spec §8.2).
    ///
    /// Differenza voluta rispetto al C#: `EnumerateFiles(…, AllDirectories)` scendeva anche nei
    /// collegamenti a cartelle (misurato su .NET 10), accreditando byte che la cancellazione — che
    /// non segue i collegamenti — non libera. Qui non si scende mai in un collegamento, come
    /// prescrive la spec originale (§7: «I symlink non vengono mai seguiti»).
    private func measureRealSize(_ path: String, isDirectory: Bool) throws -> Int64 {
        do {
            if isDirectory {
                // Un elemento-cartella diventato collegamento dopo la scansione: la cancellazione
                // rimuove solo il collegamento, quindi non si accreditano i byte della destinazione.
                if try fileSystem.itemInfo(path).kind == .symbolicLink { return 0 }
                return try sumOfFiles(under: path)
            }
            return try fileSystem.fileLength(path)
        } catch is FileSystemError {
            return 0
        }
    }

    /// Iterativa, con una pila esplicita: la versione ricorsiva scendeva di una chiamata per livello
    /// e una cartella di qualche centinaio di livelli esauriva lo stack del thread (crash del
    /// 2026-10-15). Visita in profondità nello stesso ordine della ricorsione, quindi il primo errore
    /// che interrompe la misura è lo stesso. Interna e non privata per le prove.
    func sumOfFiles(under directory: String) throws -> Int64 {
        var total: Int64 = 0
        // Per ogni cartella aperta, le voci ancora da visitare; in cima la più profonda.
        var open = [try fileSystem.contentsOfDirectory(directory).makeIterator()]
        while var entries = open.popLast() {
            guard let entry = entries.next() else { continue }
            open.append(entries)
            let info = try fileSystem.itemInfo(entry)
            switch info.kind {
            case .directory:
                open.append(try fileSystem.contentsOfDirectory(entry).makeIterator())
            case .symbolicLink where fileSystem.directoryExists(entry):
                continue
            default:
                // Un file, o un collegamento a file: come FileInfo.Length, conta la dimensione del
                // collegamento stesso.
                total += info.size
            }
        }
        return total
    }
}
