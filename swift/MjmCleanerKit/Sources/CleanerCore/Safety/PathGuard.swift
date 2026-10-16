import Foundation

/// Esito di una validazione. `canonicalPathValidated` è il percorso su cui il verdetto è stato
/// effettivamente emesso: quando permesso, è quello che va eliminato, non l'argomento originale —
/// validare una stringa e cancellarne un'altra vanificherebbe ogni controllo precedente. È vuoto
/// quando il rifiuto è emesso prima che un percorso canonico fosse disponibile.
public struct GuardVerdict: Sendable, Equatable {
    public let isAllowed: Bool
    public let reason: String
    public let canonicalPathValidated: String

    public init(isAllowed: Bool, reason: String, canonicalPathValidated: String) {
        self.isAllowed = isAllowed
        self.reason = reason
        self.canonicalPathValidated = canonicalPathValidated
    }

    public static func allow(_ canonicalPath: String) -> GuardVerdict {
        GuardVerdict(isAllowed: true, reason: "", canonicalPathValidated: canonicalPath)
    }

    public static func deny(_ reason: String, _ canonicalPath: String = "") -> GuardVerdict {
        GuardVerdict(isAllowed: false, reason: reason, canonicalPathValidated: canonicalPath)
    }
}

public protocol PathGuarding: Sendable {
    /// Valida la root dichiarata da una regola, risalendo i suoi antenati fino alla radice: se la
    /// root o un antenato è un collegamento simbolico lo risolve alla destinazione finale invece di
    /// negarlo alla cieca (su macOS "/var", "/etc" e "/tmp" sono collegamenti, e negarli renderebbe
    /// "$TMPDIR" non pulibile), e al percorso risolto applica la canonicità e solo le voci
    /// RICORSIVE della deny-list. Va invocata una volta per regola, prima degli elementi.
    func validateRoot(_ declaredRoot: String) -> GuardVerdict

    /// Valida un singolo elemento contro la root dichiarata. Presuppone che `validateRoot` sia già
    /// stata invocata con successo sulla stessa root: il controllo sui collegamenti qui risale solo
    /// fino alla root.
    func validate(_ candidatePath: String, declaredRoot: String) -> GuardVerdict

    /// Il motivo per cui una cartella va esclusa dalla discesa ricorsiva perché la deny-list la
    /// protegge, oppure `nil`. Così uno scanner pota l'intero ramo invece di produrre
    /// un'esclusione per ogni elemento al suo interno, che per "~/Documents" o "~/.ssh" ne
    /// rivelerebbe i nomi dei file. Applica solo la deny-list, non contenimento né profondità.
    func pruneReason(_ candidatePath: String) -> String?
}

/// Ultima linea di difesa: invocato immediatamente prima di ogni eliminazione, non solo quando si
/// definiscono le regole. Non lancia mai: un input malformato produce un rifiuto motivato, mai un
/// errore che un `catch` a monte potrebbe trasformare in un salto silenzioso. In Swift la regola
/// è imposta dalla firma: `validate` e `validateRoot` non sono `throws`.
///
/// Solo Swift (piano APFS, spec §12): la deny-list e la profondità minima si applicano anche al
/// percorso come lo registra il filesystem (`FileSystem.storedPath`), dopo ogni controllo
/// testuale. APFS case-insensitive ripiega più di OrdinalIgnoreCase (U+212A per "k", "ſ" per
/// "s", "ß" per "ss", NFC e NFD): un elemento scritto "~/Des\u{212A}top/x" supera i confronti
/// testuali e il kernel lo risolve in "~/Desktop/x".
public struct PathGuard: PathGuarding {
    /// Limite di sostituzioni successive durante la risoluzione dei collegamenti di una root:
    /// una catena più lunga è quasi certamente un ciclo nel doppio di test, non uno scenario
    /// reale — nega invece di girare all'infinito.
    private static let maxSymlinkResolutions = 32

    /// Gli errori di `storedPath` per cui si risale all'antenato: il componente non esiste
    /// (ENOENT, ENOTDIR) o il suo genitore non si attraversa (EACCES, EPERM). In entrambi i casi
    /// nemmeno l'eliminazione raggiunge l'oggetto, perché la ricerca del kernel è la stessa. Ogni
    /// altro errore rende il percorso non verificabile, e il percorso viene negato.
    private static let climbableErrors: Set<Int32> = [ENOENT, ENOTDIR, EACCES, EPERM]

    private let denyList: DenyList
    private let fileSystem: any FileSystem
    private let links: any LinkInspecting
    private let home: String
    /// Home e deny-list nella grafia del disco: il percorso registrato di un elemento si confronta
    /// con queste, non con quelle testuali. Una home sotto un collegamento (/var → /private/var)
    /// o scritta in un'altra normalizzazione ha sul disco un'altra grafia.
    private let storedHome: String
    private let storedDenyList: DenyList

    public init(denyList: DenyList, fileSystem: any FileSystem, links: any LinkInspecting, homeDirectory: String?) throws {
        guard let home = CanonicalPath.canonical(homeDirectory), home != "/" else {
            throw InvalidConfiguration("La home directory deve essere un percorso assoluto canonico diverso dalla radice.")
        }

        // Imposta, non solo documenta: con due home diverse fra guard e deny-list, la regola di
        // profondità (punto 4 di validate) proteggerebbe la home sbagliata.
        guard PathText.equalsIgnoringCase(home, denyList.homeDirectory) else {
            throw InvalidConfiguration("La home del PathGuard deve coincidere con quella della DenyList.")
        }

        let stored: String
        switch Self.storedForm(home, in: fileSystem) {
        case .success(let path): stored = path
        case .failure(let error):
            throw InvalidConfiguration("La home directory non è verificabile sul filesystem: \(error.description)")
        }
        guard let storedHome = CanonicalPath.canonical(stored), storedHome != "/" else {
            throw InvalidConfiguration("La home directory registrata dal filesystem deve essere un percorso assoluto canonico diverso dalla radice.")
        }

        self.denyList = denyList
        self.fileSystem = fileSystem
        self.links = links
        self.home = home
        self.storedHome = storedHome
        storedDenyList = try DenyList(homeDirectory: storedHome)
    }

    public func validateRoot(_ declaredRoot: String) -> GuardVerdict {
        let root: String
        switch Self.canonicalRoot(declaredRoot) {
        case .success(let canonical): root = canonical
        case .failure(let verdict): return verdict
        }

        let resolved: String
        switch resolveSymlinkedAncestors(root) {
        case .success(let path): resolved = path
        case .failure(let verdict): return verdict
        }

        // Due cause distinte, due messaggi distinti: un percorso risolto non canonico non
        // "coincide con la radice del filesystem" — lo fa solo il caso verificato a parte.
        guard let canonicalResolved = CanonicalPath.canonical(resolved) else {
            return .deny(String(localized: "root risolta non canonica", bundle: .module))
        }

        if canonicalResolved == "/" {
            return .deny(String(localized: "root risolta degenere: coincide con la radice del filesystem", bundle: .module))
        }

        // Solo le voci ricorsive: quelle a uguaglianza esatta ("/", "/Users", la home) proteggono
        // solo se stesse, non il permesso di guardarci dentro.
        if let reason = denyList.recursiveDeniedReason(canonicalResolved) {
            return .deny(reason, canonicalResolved)
        }

        // Come il punto 7 di validate: la root risolta si confronta anche nella grafia del disco,
        // con le sole voci ricorsive.
        switch storedForm(canonicalResolved) {
        case .failure(let error):
            return .deny(String(localized: "root non verificabile sul filesystem: \(error.description)", bundle: .module), canonicalResolved)
        case .success(let stored):
            if stored == "/" {
                return .deny(String(localized: "root risolta degenere: coincide con la radice del filesystem", bundle: .module), canonicalResolved)
            }
            if let reason = storedDenyList.recursiveDeniedReason(stored) {
                return .deny(reason, canonicalResolved)
            }
        }

        return .allow(canonicalResolved)
    }

    public func validate(_ candidatePath: String, declaredRoot: String) -> GuardVerdict {
        // 1. Rifiuto dei percorsi non canonici, prima di qualsiasi confronto. Nessuna risoluzione
        //    testuale di "." o "..": il kernel risolve ".." DOPO aver attraversato un collegamento,
        //    una risoluzione testuale lo farebbe PRIMA, facendo sparire il collegamento dalla
        //    stringa prima che la regola 5 possa vederlo. Gli elementi da eliminare arrivano
        //    sempre dall'enumerazione del filesystem, che non produce mai "..".
        guard let path = CanonicalPath.canonical(candidatePath) else {
            return .deny(String(localized: "percorso non canonico", bundle: .module))
        }

        let root: String
        switch Self.canonicalRoot(declaredRoot) {
        case .success(let canonical): root = canonical
        case .failure(let verdict): return verdict
        }

        // 2. Contenimento nella root dichiarata dalla regola che ha prodotto l'elemento.
        guard PathText.hasPrefixIgnoringCase(path, root + "/") || PathText.equalsIgnoringCase(path, root) else {
            return .deny(String(localized: "violazione del contenimento: fuori da \(root)", bundle: .module), path)
        }

        // 3. Deny-list.
        if let reason = denyList.deniedReason(path) {
            return .deny(reason, path)
        }

        // 4. Profondità minima: mai la home, mai un suo figlio diretto.
        if Self.isHomeOrDirectChild(path, of: home) {
            return .deny(String(localized: "profondità insufficiente: figlio diretto della home", bundle: .module), path)
        }

        // 5. Collegamenti simbolici fra l'elemento e la root: la root e ciò che sta sopra sono già
        //    stati verificati da validateRoot, quindi qui si risale fino a lì, non oltre.
        // Il limite è semantico (strettamente sotto la root), non una lunghezza: un ripiegamento
        // delle maiuscole non può accorciarlo.
        let rootPrefix = root + "/"
        var ancestor = PathText.parent(path)
        while let current = ancestor, PathText.hasPrefixIgnoringCase(current, rootPrefix) {
            if links.isSymbolicLink(current) {
                return .deny(String(localized: "antenato è un collegamento simbolico: \(current)", bundle: .module), path)
            }
            ancestor = PathText.parent(current)
        }

        // 6. Un elemento che coincide esattamente con la root dichiarata cancellerebbe la
        //    root per intero invece di svuotarla — il contratto di ogni regola (in
        //    particolare quelle a svuotamento) è che la root sopravvive. Lo scanner non
        //    produce mai un elemento così (ClearContents elenca solo i figli diretti della
        //    root, mai la root stessa), ma il modello di minaccia dichiara esplicitamente
        //    l'elenco manipolabile fra la scansione e la conferma. Deliberatamente l'ultimo
        //    controllo, dopo quello di profondità (punto 4): quando root e home coincidono
        //    (o la root è un figlio diretto della home), quella regola già nega con un
        //    motivo più specifico ("profondità insufficiente"), e non va scavalcata da un
        //    motivo più generico qui.
        if PathText.equalsIgnoringCase(path, root) {
            return .deny(String(localized: "l'elemento coincide con la root della regola: \(root)", bundle: .module), path)
        }

        // 7. Il percorso come lo registra il filesystem (spec §12): deny-list e profondità minima
        //    si ripetono sulla grafia del disco. Sono gli ultimi controlli, così i motivi dei
        //    rifiuti testuali restano quelli di prima. Si elimina comunque il percorso testuale:
        //    il kernel lo risolve nello stesso oggetto appena verificato.
        switch storedForm(path) {
        case .failure(let error):
            return .deny(String(localized: "percorso non verificabile sul filesystem: \(error.description)", bundle: .module), path)
        case .success(let stored):
            if let reason = storedDenyList.deniedReason(stored) {
                return .deny(reason, path)
            }
            if Self.isHomeOrDirectChild(stored, of: storedHome) {
                return .deny(String(localized: "profondità insufficiente: figlio diretto della home", bundle: .module), path)
            }
        }

        return .allow(path)
    }

    public func pruneReason(_ candidatePath: String) -> String? {
        guard let path = CanonicalPath.canonical(candidatePath) else {
            return String(localized: "percorso non canonico", bundle: .module)
        }
        if let reason = denyList.deniedReason(path) {
            return reason
        }
        // Come il punto 7 di validate.
        switch storedForm(path) {
        case .failure(let error):
            return String(localized: "percorso non verificabile sul filesystem: \(error.description)", bundle: .module)
        case .success(let stored):
            return storedDenyList.deniedReason(stored)
        }
    }

    // MARK: - Privati

    private enum Step<Value> {
        case success(Value)
        case failure(GuardVerdict)
    }

    /// Canonicalizza la root e ne rifiuta le forme degeneri: una root che coincide con la radice
    /// rende il contenimento vero per qualunque percorso assoluto, quindi privo di significato.
    private static func canonicalRoot(_ declaredRoot: String) -> Step<String> {
        guard let canonical = CanonicalPath.canonical(declaredRoot), canonical != "/" else {
            return .failure(.deny(String(localized: "root non canonica o degenere: coincide con la radice del filesystem", bundle: .module)))
        }
        return .success(canonical)
    }

    /// Risolve iterativamente i collegamenti fra gli antenati di `root` (se stessa inclusa),
    /// sostituendo ciascuno con la sua destinazione finale, finché non ne restano. Se la
    /// destinazione di un antenato non è determinabile nega, invece di proseguire alla cieca.
    private func resolveSymlinkedAncestors(_ root: String) -> Step<String> {
        var current = root

        for _ in 0..<Self.maxSymlinkResolutions {
            var substituted: String?
            var ancestor: String? = current

            while let candidate = ancestor {
                if links.isSymbolicLink(candidate) {
                    guard let target = links.resolveLinkTarget(candidate) else {
                        return .failure(.deny(
                            String(localized: "la root o un suo antenato è un collegamento simbolico la cui destinazione non è determinabile: \(candidate)", bundle: .module),
                            current))
                    }
                    // `candidate` è un prefisso in byte di `current` (lo produce PathText.parent): il taglio
                    // avviene in byte UTF-8, così un separatore che segue uno scalare "Prepend" non va perso.
                    let suffix = current.utf8.count > candidate.utf8.count ? String(decoding: current.utf8.dropFirst(candidate.utf8.count), as: UTF8.self) : ""
                    substituted = PathText.trimmingTrailingSlashes(target) + suffix
                    break
                }
                ancestor = PathText.parent(candidate)
            }

            guard let next = substituted else { return .success(current) }
            current = next
        }

        return .failure(.deny(String(localized: "troppi collegamenti simbolici annidati mentre si risolveva la root: \(root)", bundle: .module)))
    }

    private func storedForm(_ path: String) -> Result<String, FileSystemError> {
        Self.storedForm(path, in: fileSystem)
    }

    /// Il percorso come lo registra il filesystem: quello dell'antenato più profondo che esiste,
    /// `path` compreso, seguito dai componenti che mancano, presi dal testo. Un elemento sparito
    /// dopo la scansione resta verificabile, e la cancellazione che segue lo segnala «non
    /// trovato» come prima. Si risale solo con `climbableErrors`. `path` è canonico.
    private static func storedForm(_ path: String, in fileSystem: any FileSystem) -> Result<String, FileSystemError> {
        var existing = path
        var missing: [String] = []
        while true {
            do {
                let stored = try fileSystem.storedPath(existing)
                return .success(missing.reversed().reduce(stored) { PathText.join($0, $1) })
            } catch let error as FileSystemError {
                guard climbableErrors.contains(error.code), let parent = PathText.parent(existing), !parent.isEmpty else {
                    return .failure(error)
                }
                missing.append(PathText.fileName(existing))
                existing = parent
            } catch {
                return .failure(FileSystemError(code: EIO, path: existing))
            }
        }
    }

    private static func isHomeOrDirectChild(_ path: String, of home: String) -> Bool {
        if PathText.equalsIgnoringCase(path, home) { return true }
        guard PathText.hasPrefixIgnoringCase(path, home + "/") else { return false }
        // hasPrefixIgnoringCase garantisce che il prefisso riconosciuto abbia lo stesso numero di scalari di home + "/".
        return !path.unicodeScalars.dropFirst(home.unicodeScalars.count + 1).contains("/")
    }
}
