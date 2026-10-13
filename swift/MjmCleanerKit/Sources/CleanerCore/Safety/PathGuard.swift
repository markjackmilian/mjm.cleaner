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
public struct PathGuard: PathGuarding {
    /// Limite di sostituzioni successive durante la risoluzione dei collegamenti di una root: una
    /// catena più lunga è quasi certamente un ciclo — nega invece di girare all'infinito.
    private static let maxSymlinkResolutions = 32

    private let denyList: DenyList
    private let links: any LinkInspecting
    private let home: String

    public init(denyList: DenyList, links: any LinkInspecting, homeDirectory: String?) throws {
        guard let home = CanonicalPath.canonical(homeDirectory), home != "/" else {
            throw InvalidConfiguration("La home directory deve essere un percorso assoluto canonico diverso dalla radice.")
        }

        // Imposta, non solo documenta: con due home diverse fra guard e deny-list, la regola di
        // profondità (punto 4 di validate) proteggerebbe la home sbagliata.
        guard PathText.equalsIgnoringCase(home, denyList.homeDirectory) else {
            throw InvalidConfiguration("La home del PathGuard deve coincidere con quella della DenyList.")
        }

        self.denyList = denyList
        self.links = links
        self.home = home
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
        if isHomeOrDirectChild(path) {
            return .deny(String(localized: "profondità insufficiente: figlio diretto della home", bundle: .module), path)
        }

        // 5. Collegamenti simbolici fra l'elemento e la root: la root e ciò che sta sopra sono già
        //    stati verificati da validateRoot, quindi qui si risale fino a lì, non oltre.
        var ancestor = PathText.parent(path)
        while let current = ancestor, current.utf16.count > root.utf16.count {
            if links.isSymbolicLink(current) {
                return .deny(String(localized: "antenato è un collegamento simbolico: \(current)", bundle: .module), path)
            }
            ancestor = PathText.parent(current)
        }

        // 6. Un elemento che coincide con la root dichiarata cancellerebbe la root invece di
        //    svuotarla. Lo scanner non lo produce mai, ma l'elenco è manipolabile fra scansione e
        //    conferma. Deliberatamente dopo il punto 4, che nega con un motivo più specifico quando
        //    la root è la home o un suo figlio diretto.
        if PathText.equalsIgnoringCase(path, root) {
            return .deny(String(localized: "l'elemento coincide con la root della regola: \(root)", bundle: .module), path)
        }

        return .allow(path)
    }

    public func pruneReason(_ candidatePath: String) -> String? {
        guard let path = CanonicalPath.canonical(candidatePath) else {
            return String(localized: "percorso non canonico", bundle: .module)
        }
        return denyList.deniedReason(path)
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
                    let suffix = current.count > candidate.count ? String(current.dropFirst(candidate.count)) : ""
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

    private func isHomeOrDirectChild(_ path: String) -> Bool {
        if PathText.equalsIgnoringCase(path, home) { return true }
        guard PathText.hasPrefixIgnoringCase(path, home + "/") else { return false }
        return !path.dropFirst(home.count + 1).contains("/")
    }
}
