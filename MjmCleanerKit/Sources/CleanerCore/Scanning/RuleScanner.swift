import Darwin
import Foundation

/// Interpreta una singola regola. Non segue mai i collegamenti simbolici.
public struct RuleScanner: Sendable {
    private let fileSystem: any FileSystem
    private let pathGuard: any PathGuarding
    private let links: any LinkInspecting
    private let clock: any WallClock

    private static let projectMarkers = ["*.csproj", "*.fsproj", "*.vbproj", "*.sln", "*.slnx"]

    /// Nomi di cartelle di metadati dei sistemi di controllo versione: mai attraversate.
    private static let vcsDirectoryNames = [".git", ".hg", ".svn"]

    /// Prima data considerata un vero timestamp anziché una sentinella (1990-01-01 UTC).
    private static let minDeterminableStamp = Date(timeIntervalSince1970: 631_152_000)

    public init(fileSystem: any FileSystem, pathGuard: any PathGuarding, links: any LinkInspecting, clock: any WallClock) {
        self.fileSystem = fileSystem
        self.pathGuard = pathGuard
        self.links = links
        self.clock = clock
    }

    /// Lancia solo `CancellationError`: ogni altro problema diventa un errore o un'esclusione
    /// dell'esito.
    public func scan(_ rule: CleanupRule) throws -> RuleScanOutcome {
        var accumulator = Accumulator()

        // Root assente: categoria vuota, non errore.
        guard fileSystem.directoryExists(rule.root) else { return accumulator.outcome }

        // La root si valida una volta sola, risalendo fino alla radice del filesystem: se la root
        // o un suo antenato è un collegamento, ogni elemento trovato sotto punterebbe altrove. È
        // il caso di chi sposta ~/Library/Caches su un disco esterno con un collegamento.
        let rootVerdict = pathGuard.validateRoot(rule.root)
        guard rootVerdict.isAllowed else {
            accumulator.exclusions.append(GuardExclusion(path: rule.root, reason: rootVerdict.reason))
            return accumulator.outcome
        }

        // Le cartelle escluse nelle Impostazioni si confrontano anche con la root risolta e nella
        // grafia del disco. Un'esclusione non valida o non verificabile ferma la regola, come la
        // root esclusa o sotto un'esclusione: la regola non produce nulla.
        let excluded: ExcludedFolders
        switch ExcludedFolders.resolve(
            rule.excludedPaths, root: rule.root, resolvedRoot: rootVerdict.canonicalPathValidated, fileSystem: fileSystem, links: links) {
        case .success(let folders): excluded = folders
        case .failure(let rejection):
            accumulator.exclusions.append(GuardExclusion(path: rule.root, reason: rejection.reason))
            return accumulator.outcome
        }
        if let reason = excluded.excludedReason(rule.root) {
            accumulator.exclusions.append(GuardExclusion(path: rule.root, reason: reason))
            return accumulator.outcome
        }

        switch rule.mode {
        case .clearContents:
            try scanContents(rule, excluded, &accumulator)
        case .matchingFiles:
            try scanFiles(rule, excluded, &accumulator)
        case .matchingDirs:
            try scanDirectories(rule, excluded, &accumulator)
        }

        return accumulator.outcome
    }

    // MARK: - Classificazione degli errori

    /// Stessa mappatura di `RuleScanner.Describe` in C#, applicata all'errno da cui .NET ricavava
    /// il tipo di eccezione: EACCES/EPERM/EBADF → accesso negato (UnauthorizedAccessException),
    /// ENOENT → non trovato, ENOTEMPTY → non vuota, qualunque altro errno → in uso (in C# ogni
    /// IOException residua cadeva lì). Un errore che non viene dal filesystem è "altro".
    static func describe(_ path: String, _ error: any Error) -> ScanError {
        guard let fileSystemError = error as? FileSystemError else {
            return ScanError(path: path, kind: .other, message: String(describing: error))
        }

        let kind: ScanErrorKind
        switch fileSystemError.code {
        case EACCES, EPERM, EBADF: kind = .accessDenied
        case ENOENT: kind = .notFound
        case ENOTEMPTY: kind = .notEmpty
        default: kind = .inUse
        }
        return ScanError(path: path, kind: kind, message: fileSystemError.message)
    }

    /// Gli errori "previsti" (in C#: `UnauthorizedAccessException` o `IOException`).
    static func isExpected(_ error: any Error) -> Bool {
        error is FileSystemError
    }

    // MARK: - Modalità

    private func scanContents(_ rule: CleanupRule, _ excluded: ExcludedFolders, _ accumulator: inout Accumulator) throws {
        for entry in enumerate(rule.root, &accumulator.errors) {
            try Task.checkCancellation()

            guard Self.matchesGlobs(PathText.fileName(entry), rule) else { continue }

            // Il verdetto del guard precede qualunque lettura di statistiche: per una cartella
            // negata (es. "~/Library/Keychains") calcolarle richiederebbe di attraversarla, e gli
            // errori di lettura sui file privati al suo interno finirebbero nell'elenco mostrato
            // all'utente prima ancora che l'elemento risulti escluso.
            let verdict = pathGuard.validate(entry, declaredRoot: rule.root)
            guard verdict.isAllowed else {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: verdict.reason))
                continue
            }

            // Anche le esclusioni dell'utente precedono le statistiche: un figlio escluso, o che
            // contiene una cartella esclusa, non si attraversa nemmeno per misurarlo.
            if let reason = excluded.candidateReason(entry) {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: reason))
                continue
            }

            let isLink = links.isSymbolicLink(entry)
            let isDirectory = !isLink && fileSystem.directoryExists(entry)
            let size: Int64

            if isLink {
                // Non si attraversa mai il bersaglio per calcolarne la dimensione (resta 0). Il
                // filtro di età legge le date del collegamento stesso (lstat), come FileInfo e
                // DirectoryInfo di .NET: il commento C# che parlava del bersaglio era impreciso.
                guard accept(entry, rule, &accumulator.errors) else { continue }
                size = 0
            } else if isDirectory {
                // Età e dimensione nello stesso attraversamento: l'mtime di una cartella non cambia
                // quando un file interno viene riscritto sul posto, quindi conta il timestamp più
                // recente dell'albero.
                let stats = try directoryStats(entry, &accumulator.errors)
                // Scomparsa o illeggibile fra l'enumerazione e questo punto: non va proposta,
                // altrimenti comparirebbe sia fra gli errori sia fra gli elementi.
                guard stats.determinable, acceptStamp(stats.newest, rule.minAge) else { continue }
                size = stats.size
            } else {
                // Un file scomparso fra enumerazione e lettura della dimensione va annotato come
                // errore, non proposto con dimensione 0.
                guard let fileSize = tryFileSize(entry, &accumulator.errors) else { continue }
                guard accept(entry, rule, &accumulator.errors) else { continue }
                size = fileSize
            }

            if let minSize = rule.minSizeBytes, size < minSize { continue }

            accumulator.items.append(ScanItem(path: entry, sizeBytes: size, isDirectory: isDirectory, declaredRoot: rule.root))
        }
    }

    private func scanFiles(_ rule: CleanupRule, _ excluded: ExcludedFolders, _ accumulator: inout Accumulator) throws {
        var open = OpenDirectories()
        enter(rule.root, depth: 0, rule, &open, &accumulator.errors)

        while let (entry, _, depth) = open.next() {
            try Task.checkCancellation()

            if links.isSymbolicLink(entry) { continue }

            if fileSystem.directoryExists(entry) {
                // Ramo saltato per intero: sotto ".git" vivono i pack file con l'intera storia del
                // repository, indistinguibili da un file grande legittimo. Non è nella deny-list,
                // che ragiona per percorsi assoluti fissi, non per nomi che compaiono ovunque.
                if Self.isVersionControlDirectory(PathText.fileName(entry)) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: Self.vcsExclusionReason))
                    continue
                }

                // Pota il ramo intero: un'esclusione per cartella protetta invece di una per file,
                // che ne rivelerebbe i nomi. Solo la deny-list: la regola di profondità di validate
                // poterebbe ogni cartella legittima di primo livello sotto la home.
                if let pruneReason = pathGuard.pruneReason(entry) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: pruneReason))
                    continue
                }

                // Le cartelle escluse nelle Impostazioni si potano come quelle della deny-list.
                if let reason = excluded.excludedReason(entry) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: reason))
                    continue
                }

                // Un pacchetto macOS (una macchina virtuale, un'app, un .logarchive) è un documento
                // unico: cancellarne un file interno lo rompe. Non si entra mai, si valuta intero,
                // con i glob applicati al suo nome.
                if fileSystem.isPackage(entry) {
                    if Self.matchesGlobs(PathText.fileName(entry), rule) {
                        try proposeWholeDirectory(entry, rule, excluded, &accumulator)
                    }
                    continue
                }

                enter(entry, depth: depth + 1, rule, &open, &accumulator.errors)
                continue
            }

            guard Self.matchesGlobs(PathText.fileName(entry), rule), accept(entry, rule, &accumulator.errors) else { continue }
            guard let size = tryFileSize(entry, &accumulator.errors) else { continue }
            if let minSize = rule.minSizeBytes, size < minSize { continue }

            let verdict = pathGuard.validate(entry, declaredRoot: rule.root)
            guard verdict.isAllowed else {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: verdict.reason))
                continue
            }

            accumulator.items.append(ScanItem(path: entry, sizeBytes: size, isDirectory: false, declaredRoot: rule.root))
        }
    }

    /// Una cartella che si propone per intero: un pacchetto trovato da `scanFiles` o un `bin`/`obj`
    /// trovato da `scanDirectories`. Il guard decide prima delle statistiche, come in
    /// `scanContents`, e così le esclusioni dell'utente: eliminarla cancellerebbe anche una
    /// cartella esclusa al suo interno. Le statistiche attraversano l'intero albero; età e soglia
    /// valgono sul timestamp più recente e sul totale, e un timestamp non determinabile la scarta.
    private func proposeWholeDirectory(_ directory: String, _ rule: CleanupRule, _ excluded: ExcludedFolders, _ accumulator: inout Accumulator) throws {
        let verdict = pathGuard.validate(directory, declaredRoot: rule.root)
        guard verdict.isAllowed else {
            accumulator.exclusions.append(GuardExclusion(path: directory, reason: verdict.reason))
            return
        }

        if let reason = excluded.candidateReason(directory) {
            accumulator.exclusions.append(GuardExclusion(path: directory, reason: reason))
            return
        }

        let stats = try directoryStats(directory, &accumulator.errors)
        guard stats.determinable, acceptStamp(stats.newest, rule.minAge) else { return }
        if let minSize = rule.minSizeBytes, stats.size < minSize { return }

        accumulator.items.append(ScanItem(path: directory, sizeBytes: stats.size, isDirectory: true, declaredRoot: rule.root))
    }

    /// Cerca in profondità cartelle il cui nome corrisponde ai pattern (bin/obj, pacchetti NuGet).
    /// Una cartella trovata non viene mai attraversata oltre: sarà eliminata per intero.
    private func scanDirectories(_ rule: CleanupRule, _ excluded: ExcludedFolders, _ accumulator: inout Accumulator) throws {
        var open = OpenDirectories()
        enter(rule.root, depth: 0, rule, &open, &accumulator.errors)

        while let (entry, directory, depth) = open.next() {
            try Task.checkCancellation()

            if links.isSymbolicLink(entry) || !fileSystem.directoryExists(entry) { continue }

            let name = PathText.fileName(entry)

            // Stesso ramo saltato di scanFiles, prima di ogni altra valutazione: non si entra mai
            // in ".git"/".hg"/".svn" e non li si propone, anche se il nome corrispondesse.
            if Self.isVersionControlDirectory(name) {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: Self.vcsExclusionReason))
                continue
            }

            // Una cartella esclusa nelle Impostazioni non si propone e non si attraversa, anche se
            // si chiama "bin" o "obj".
            if let reason = excluded.excludedReason(entry) {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: reason))
                continue
            }

            // Un'esclusione è un rifiuto esplicito, non un "continua a cercare più in basso":
            // scendervi proporrebbe una singola versione di un pacchetto escluso.
            if Self.matchesAnyGlob(name, rule.excludeGlobs) { continue }

            var matches = Self.matchesAnyGlob(name, rule.includeGlobs)
            if matches && rule.requiresProjectMarker {
                matches = hasProjectMarker(directory, &accumulator.errors)
            }

            if matches {
                try proposeWholeDirectory(entry, rule, excluded, &accumulator)
                // Trovata: non si scende oltre, l'intera cartella verrà eliminata.
                continue
            }

            if let pruneReason = pathGuard.pruneReason(entry) {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: pruneReason))
                continue
            }

            enter(entry, depth: depth + 1, rule, &open, &accumulator.errors)
        }
    }

    // MARK: - Supporto

    private struct Accumulator {
        var items: [ScanItem] = []
        var errors: [ScanError] = []
        var exclusions: [GuardExclusion] = []

        var outcome: RuleScanOutcome { RuleScanOutcome(items: items, errors: errors, exclusions: exclusions) }
    }

    /// Le cartelle aperte di una visita in profondità, dalla più esterna: per ognuna la profondità
    /// e le voci ancora da visitare. Prende il posto della ricorsione, che scendeva di una chiamata
    /// per livello e con qualche centinaio di livelli esauriva lo stack del thread (crash del
    /// 2026-10-15): le voci escono nello stesso ordine, in profondità e nell'ordine di elenco, e
    /// una sottocartella si visita per intero prima delle voci che la seguono.
    private struct OpenDirectories {
        private var stack: [(path: String, depth: Int, entries: IndexingIterator<[String]>)] = []

        mutating func push(_ path: String, depth: Int, _ entries: [String]) {
            stack.append((path, depth, entries.makeIterator()))
        }

        /// La prossima voce da visitare, con la cartella che la contiene e la profondità di questa.
        mutating func next() -> (entry: String, directory: String, depth: Int)? {
            while let top = stack.indices.last {
                if let entry = stack[top].entries.next() {
                    return (entry, stack[top].path, stack[top].depth)
                }
                stack.removeLast()
            }
            return nil
        }
    }

    /// Elenca `directory` e la apre nella visita, se non supera la profondità massima: è la
    /// guardia che la versione ricorsiva aveva in testa, quindi oltre `maxDepth` non si elenca.
    private func enter(_ directory: String, depth: Int, _ rule: CleanupRule, _ open: inout OpenDirectories, _ errors: inout [ScanError]) {
        guard depth <= rule.maxDepth else { return }
        open.push(directory, depth: depth, enumerate(directory, &errors))
    }

    private static var vcsExclusionReason: String {
        String(localized: "repository di controllo versione: ramo saltato per non cancellare la storia del progetto", bundle: .module)
    }

    private static func isVersionControlDirectory(_ name: String) -> Bool {
        vcsDirectoryNames.contains { PathText.equalsIgnoringCase($0, name) }
    }

    /// Vera se la cartella che contiene il candidato ospita un file di progetto. Senza questo
    /// vincolo una root mal configurata (es. "/usr") porterebbe a proporre "/usr/bin": il
    /// PathGuard la bloccherebbe comunque, ma questo è il primo filtro.
    private func hasProjectMarker(_ parentDirectory: String, _ errors: inout [ScanError]) -> Bool {
        for sibling in enumerate(parentDirectory, &errors) {
            // Un marcatore è sempre un file: una cartella chiamata "x.sln" non deve soddisfarlo.
            if fileSystem.directoryExists(sibling) { continue }
            let name = PathText.fileName(sibling)
            if Self.projectMarkers.contains(where: { SimpleGlob.matches($0, name) }) { return true }
        }
        return false
    }

    /// Filtro di età sul percorso stesso (file o collegamento), mai per le cartelle in
    /// clearContents, la cui età si calcola sull'albero con `acceptStamp`.
    private func accept(_ path: String, _ rule: CleanupRule, _ errors: inout [ScanError]) -> Bool {
        guard let minAge = rule.minAge else { return true }
        do {
            return acceptStamp(try fileSystem.itemInfo(path).newestStamp, minAge)
        } catch let error as FileSystemError where error.code == ENOENT {
            // .NET restituiva la sentinella 1601-01-01 senza lanciare: età massima, filtro superato.
            return true
        } catch {
            errors.append(Self.describe(path, error))
            return false
        }
    }

    private func acceptStamp(_ stamp: Date, _ minAge: TimeInterval?) -> Bool {
        guard let minAge else { return true }
        return clock.now.timeIntervalSince(stamp) >= minAge
    }

    private static func matchesGlobs(_ name: String, _ rule: CleanupRule) -> Bool {
        !matchesAnyGlob(name, rule.excludeGlobs) && matchesAnyGlob(name, rule.includeGlobs)
    }

    private static func matchesAnyGlob(_ name: String, _ globs: [String]) -> Bool {
        globs.contains { SimpleGlob.matches($0, name) }
    }

    /// Elenca una cartella senza mai far fallire l'intera scansione per un ramo illeggibile: mount
    /// virtuali come "~/Library/Developer/CoreDevice/DeviceFS" rispondono con errori imprevedibili,
    /// e l'utente non può essere tenuto a escludere a mano ogni percorso problematico.
    private func enumerate(_ directory: String, _ errors: inout [ScanError]) -> [String] {
        do {
            return try fileSystem.contentsOfDirectory(directory)
        } catch {
            errors.append(Self.describe(directory, error))
            return []
        }
    }

    /// Dimensione totale, timestamp più recente e determinabilità di una cartella in un solo
    /// attraversamento, saltando i collegamenti. La determinabilità riguarda solo il timestamp
    /// della cartella passata: una sottocartella scomparsa contribuisce 0 e non invalida il totale.
    ///
    /// Iterativa, con una pila esplicita, come `CleanEngine.sumOfFiles`: la versione ricorsiva
    /// scendeva di una chiamata per livello e una cartella di qualche centinaio di livelli
    /// esauriva lo stack del thread già in analisi. Visita in profondità nello stesso ordine della
    /// ricorsione, quindi registra gli stessi errori nello stesso ordine.
    private func directoryStats(_ directory: String, _ errors: inout [ScanError]) throws -> (size: Int64, newest: Date, determinable: Bool) {
        var total: Int64 = 0
        let ownStamp = readDirectoryStamp(directory, &errors)
        var newest = ownStamp ?? .distantPast
        // Per ogni cartella aperta, le voci ancora da visitare; in cima la più profonda.
        var open = [enumerate(directory, &errors).makeIterator()]

        while var entries = open.popLast() {
            guard let entry = entries.next() else { continue }
            open.append(entries)
            try Task.checkCancellation()

            if links.isSymbolicLink(entry) { continue }

            if fileSystem.directoryExists(entry) {
                // Come la ricorsione: prima il timestamp della sottocartella, poi il suo elenco.
                // Senza timestamp determinabile contribuisce solo con il contenuto.
                if let stamp = readDirectoryStamp(entry, &errors), stamp > newest { newest = stamp }
                open.append(enumerate(entry, &errors).makeIterator())
            } else {
                let file = fileSizeAndStamp(entry, &errors)
                total += file.size
                if file.stamp > newest { newest = file.stamp }
            }
        }

        return (total, newest, ownStamp != nil)
    }

    /// Il timestamp più recente di una cartella, o `nil` se non è determinabile. Su una cartella
    /// scomparsa .NET non lanciava ma restituiva la sentinella 1601-01-01: per questo `ENOENT`
    /// produce `nil` senza registrare errori. Le date precedenti al 1990 restano trattate come
    /// sentinelle, come in C#.
    private func readDirectoryStamp(_ path: String, _ errors: inout [ScanError]) -> Date? {
        do {
            let stamp = try fileSystem.itemInfo(path).newestStamp
            return stamp < Self.minDeterminableStamp ? nil : stamp
        } catch let error as FileSystemError where error.code == ENOENT {
            return nil
        } catch {
            errors.append(Self.describe(path, error))
            return nil
        }
    }

    /// Dimensione e timestamp di un file sommato dentro una cartella, in un solo accesso, per non
    /// registrare due errori per lo stesso motivo.
    private func fileSizeAndStamp(_ path: String, _ errors: inout [ScanError]) -> (size: Int64, stamp: Date) {
        do {
            let info = try fileSystem.itemInfo(path)
            // Come FileInfo.Length di .NET su una cartella.
            guard info.kind != .directory else { throw FileSystemError(code: ENOENT, path: path) }
            return (info.size, info.newestStamp)
        } catch {
            errors.append(Self.describe(path, error))
            return (0, clock.now)
        }
    }

    /// Dimensione di un file che diventerà esso stesso un elemento. Un fallimento "non trovato"
    /// restituisce `nil` (l'elemento non va proposto); ogni altro fallimento è registrato e
    /// l'elemento resta proposto con dimensione 0, come in C#.
    private func tryFileSize(_ path: String, _ errors: inout [ScanError]) -> Int64? {
        do {
            return try fileSystem.fileLength(path)
        } catch {
            let scanError = Self.describe(path, error)
            errors.append(scanError)
            return scanError.kind == .notFound ? nil : 0
        }
    }
}
