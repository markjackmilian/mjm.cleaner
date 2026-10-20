import Darwin

/// Le cartelle escluse nelle Impostazioni, viste da una regola (spec
/// `2026-10-20-excluded-folders-canonical-design.md`). Un'esclusione si confronta in più forme: il
/// testo com'è scritto, la grafia del disco (`FileSystem.storedForm`) e, se questa è un
/// collegamento, la grafia del disco della sua destinazione finale. Anche il percorso di un
/// elemento ha più forme: com'è, sotto la root risolta da `validateRoot` e sotto la grafia del
/// disco della root. Lo scanner non segue mai i collegamenti e `readdir` dà i nomi come stanno sul
/// disco, quindi sotto la root la grafia del disco di un elemento è quella della root seguita dal
/// suffisso. Così un'esclusione vale anche scritta attraverso un collegamento, sotto "/var" con una
/// root "/private/var/…", in un'altra normalizzazione Unicode o con un'equivalenza di APFS (U+212A,
/// "ß"). Il confronto ignora le maiuscole, come la deny-list: aggiungere forme può solo escludere
/// di più.
///
/// «/» si riduce alla stringa vuota, e `isSameOrUnder(path, "")` è vero per ogni percorso
/// assoluto: escludere la radice esclude tutto, che è la direzione sicura.
struct ExcludedFolders: Sendable {
    /// Il motivo per cui la regola non produce nulla: un'esclusione non valida o non verificabile,
    /// o la root non verificabile. «Non verificabile» vuol dire negare, come nel `PathGuard`.
    struct Rejection: Error, Equatable {
        let reason: String
    }

    /// Le forme di tutte le esclusioni.
    private let folders: [String]
    private let root: String
    /// Le forme della root diverse da quella dichiarata: la root risolta e la grafia del disco.
    private let alternativeRoots: [String]

    private init(folders: [String], root: String, alternativeRoots: [String]) {
        self.folders = folders
        self.root = root
        self.alternativeRoots = alternativeRoots
    }

    /// Le esclusioni di una regola, con le forme della root e di ogni esclusione già calcolate:
    /// una chiamata per regola, dopo `validateRoot`. Senza esclusioni non interroga il filesystem.
    static func resolve(
        _ excluded: [String], root: String, resolvedRoot: String,
        fileSystem: any FileSystem, links: any LinkInspecting
    ) -> Result<ExcludedFolders, Rejection> {
        let root = PathText.trimmingTrailingSlashes(root)
        guard !excluded.isEmpty else {
            return .success(ExcludedFolders(folders: [], root: root, alternativeRoots: []))
        }

        var folders: [String] = []
        for path in excluded {
            switch forms(of: path, fileSystem, links) {
            case .success(let forms): folders += forms
            case .failure(let rejection): return .failure(rejection)
            }
        }

        let storedRoot: String
        switch fileSystem.storedForm(resolvedRoot) {
        case .success(let stored): storedRoot = stored
        case .failure(let error):
            return .failure(Rejection(reason: String(localized: "root non verificabile sul filesystem: \(error.description)", bundle: .module)))
        }

        var roots = [root]
        for candidate in [resolvedRoot, storedRoot].map(PathText.trimmingTrailingSlashes)
        where !candidate.isEmpty && !roots.contains(where: { PathText.equalsIgnoringCase($0, candidate) }) {
            roots.append(candidate)
        }
        return .success(ExcludedFolders(folders: folders, root: root, alternativeRoots: Array(roots.dropFirst())))
    }

    static var excludedReason: String {
        String(localized: "cartella esclusa nelle Impostazioni", bundle: .module)
    }

    static var containsReason: String {
        String(localized: "contiene una cartella esclusa nelle Impostazioni", bundle: .module)
    }

    /// Il motivo per non entrare in una cartella e non proporla: coincide con una cartella esclusa
    /// o sta sotto una di esse. `nil` se nessuna esclusione la riguarda.
    func excludedReason(_ path: String) -> String? {
        let excluded = forms(path).contains { form in
            folders.contains { PathText.isSameOrUnder(form, $0) }
        }
        return excluded ? Self.excludedReason : nil
    }

    /// Il motivo per non proporre un candidato: oltre ai casi di `excludedReason`, una cartella
    /// esclusa sta sotto di lui, ed eliminarlo cancellerebbe anche quella.
    func candidateReason(_ path: String) -> String? {
        if let reason = excludedReason(path) { return reason }
        let containsExcluded = forms(path).contains { form in
            folders.contains { PathText.hasPrefixIgnoringCase($0, form + "/") }
        }
        return containsExcluded ? Self.containsReason : nil
    }

    /// Le forme di un'esclusione, tutte senza «/» finali: il testo, la grafia del disco e, se
    /// questa è un collegamento, la grafia del disco della destinazione finale. Un testo che non è
    /// un percorso assoluto canonico, o una forma che non si riesce a ricavare, rifiuta la regola.
    private static func forms(of excluded: String, _ fileSystem: any FileSystem, _ links: any LinkInspecting) -> Result<[String], Rejection> {
        guard let canonical = CanonicalPath.canonical(excluded) else {
            return .failure(Rejection(reason: String(localized: "cartella esclusa con un percorso non valido: «\(excluded)»", bundle: .module)))
        }
        var forms = [PathText.trimmingTrailingSlashes(canonical)]

        let stored: String
        switch fileSystem.storedForm(canonical) {
        case .success(let path): stored = path
        case .failure(let error): return .failure(unverifiable(error))
        }
        forms.append(PathText.trimmingTrailingSlashes(stored))

        // `storedPath` non segue l'ultimo componente: un'esclusione che è un collegamento vale
        // anche per la sua destinazione. Una destinazione non determinabile è un ciclo, o un
        // collegamento che non si legge più.
        guard links.isSymbolicLink(stored) else { return .success(forms) }
        guard let target = links.resolveLinkTarget(stored) else {
            return .failure(unverifiable(FileSystemError(code: ELOOP, path: stored)))
        }
        switch fileSystem.storedForm(target) {
        case .success(let path): forms.append(PathText.trimmingTrailingSlashes(path))
        case .failure(let error): return .failure(unverifiable(error))
        }
        return .success(forms)
    }

    private static func unverifiable(_ error: FileSystemError) -> Rejection {
        Rejection(reason: String(localized: "cartella esclusa non verificabile sul filesystem: \(error.description)", bundle: .module))
    }

    /// Il percorso com'è e, se sta sotto la root dichiarata, lo stesso suffisso sotto ogni forma
    /// alternativa della root. Un prefisso riconosciuto senza maiuscole occupa lo stesso numero di
    /// scalari della root (`PathText.hasPrefixIgnoringCase`).
    private func forms(_ path: String) -> [String] {
        guard !alternativeRoots.isEmpty, PathText.isSameOrUnder(path, root) else { return [path] }
        let suffix = path.unicodeScalars.dropFirst(root.unicodeScalars.count)
        return [path] + alternativeRoots.map { alternative in
            var scalars = String.UnicodeScalarView()
            scalars.append(contentsOf: alternative.unicodeScalars)
            scalars.append(contentsOf: suffix)
            return String(scalars)
        }
    }
}
