import Foundation

/// Percorsi che non devono mai essere eliminati. Non configurabile dall'interfaccia: è l'ultima
/// linea di difesa, non una preferenza.
public struct DenyList: Sendable {
    /// La home configurata, normalizzata (assoluta, senza "/" finale). Esposta perché
    /// `PathGuard` verifichi, nel proprio inizializzatore, di riferirsi alla stessa home: due home
    /// diverse fra guard e deny-list proteggerebbero la home sbagliata.
    public let homeDirectory: String

    private let deniedExact: [String]
    private let denied: [String]
    private let exceptions: [String]

    public init(homeDirectory: String?) throws {
        guard let homeDirectory, homeDirectory.utf8.first == UInt8(ascii: "/"), homeDirectory != "/" else {
            throw InvalidConfiguration("La home directory deve essere un percorso assoluto diverso dalla radice.")
        }

        let home = PathText.trimmingTrailingSlashes(homeDirectory)

        // Validato DOPO la normalizzazione, non prima: un argomento come "//" supera indisturbato
        // il controllo sul valore grezzo qui sopra (non è né vuoto né "/"), ma la rimozione dei
        // "/" finali lo riduce a "" — a quel punto la home smette di essere un confine e la regola
        // su "/Users" si autoannulla, perché isSameOrUnder(path, "") è vero per qualunque percorso
        // assoluto. "/Users" grezzo degenera la stessa regola allo stesso modo.
        guard !home.isEmpty, !PathText.equalsIgnoringCase(home, "/Users") else {
            throw InvalidConfiguration(
                "La home directory deve restare un percorso assoluto non degenere, e diverso da \"/Users\", dopo la normalizzazione.")
        }

        self.homeDirectory = home

        // Uguaglianza esatta: proteggono solo se stesse, non un intero sottoalbero. Un confronto
        // ricorsivo su "/" o "/Users" negherebbe rispettivamente l'intero filesystem o l'intera
        // home di ogni utente, incluse le eccezioni sotto la home dell'utente corrente.
        deniedExact = ["/", "/Users", home]

        denied = [
            "/System", "/usr", "/bin", "/sbin", "/etc", "/Applications", "/Library",
            "/Volumes", "/private/etc", "/private/var/db", "/private/var/root", "/Network", "/cores", "/opt",
            "\(home)/Documents",
            "\(home)/Desktop",
            "\(home)/Pictures",
            "\(home)/Movies",
            "\(home)/Music",
            "\(home)/Library/Application Support",
            "\(home)/Library/Mobile Documents",
            // Da macOS 12, OneDrive, Dropbox e Google Drive montano qui i documenti dell'utente:
            // proteggere iCloud (Mobile Documents) e non questi sarebbe un'asimmetria arbitraria
            // che costa dati.
            "\(home)/Library/CloudStorage",
            "\(home)/Library/Keychains",
            // Solo la sottocartella con le identità di firma e i profili di provisioning:
            // "Library/Developer" resta pulibile (DerivedData è una categoria dell'app;
            // Archives non lo è più — vedi CategoryCatalog — ma resta un percorso legittimo,
            // non una cartella di sistema), quindi non va negato in blocco.
            "\(home)/Library/Developer/Xcode/UserData",
            "\(home)/.ssh",
            "\(home)/.gnupg",
            // Deve restare prima della voce "Containers" in blocco qui sotto: essendo più
            // specifica, vince nel ciclo e la motivazione restituita nomina Docker invece della
            // cartella generica.
            "\(home)/Library/Containers/com.docker.docker",
            "\(home)/Library/Messages",
            "\(home)/Library/Mail",
            "\(home)/Library/Safari",
            "\(home)/Library/Preferences",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Application Scripts",
            "\(home)/Library/Containers",
            "\(home)/.aws",
            "\(home)/.kube",
            "\(home)/.docker",
            // OrbStack: socket, configurazione e chiavi SSH della sua macchina virtuale. Il suo
            // group container è già coperto da "Library/Group Containers".
            "\(home)/.orbstack",
            // OrbStack monta qui, in NFS, i dati del motore (volumi, immagini, container): si
            // puliscono solo dalla pagina Docker, attraverso la CLI.
            "\(home)/OrbStack",
            "\(home)/.config",
            "\(home)/.password-store",
            "\(home)/.local",
            "\(home)/Applications",
            "\(home)/Public",
            "\(home)/Sites",
        ]

        exceptions = ["/Library/Caches", "/Library/Logs"]
    }

    /// Il motivo per cui il percorso è negato, oppure `nil` se è permesso. Il percorso deve
    /// essere già canonico: un percorso nullo, vuoto, relativo o non canonico viene negato per
    /// sicurezza (fail-closed), perché altrimenti potrebbe scavalcare le eccezioni, che sono
    /// ricorsive e valutate per prime.
    public func deniedReason(_ canonicalPath: String?) -> String? {
        guard let path = CanonicalPath.canonical(canonicalPath) else {
            return String(localized: "percorso non canonico", bundle: .module)
        }

        for allowed in exceptions where PathText.isSameOrUnder(path, allowed) {
            return nil
        }

        for exact in deniedExact where PathText.equalsIgnoringCase(path, exact) {
            return String(localized: "percorso protetto: \(exact)", bundle: .module)
        }

        return otherUsersReason(path) ?? recursiveReason(path)
    }

    public func isDenied(_ canonicalPath: String?) -> Bool {
        deniedReason(canonicalPath) != nil
    }

    /// Come `deniedReason`, ma ignora le voci a uguaglianza esatta ("/", "/Users", la home
    /// configurata): quelle proteggono solo se stesse, non un intero sottoalbero (vedi il
    /// commento sopra `deniedExact`). Ha senso negare l'ELEMENTO "/Users/tester" stesso
    /// (non lo si può cancellare), ma non ha senso negare la ROOT di una scansione "/Users/tester"
    /// per lo stesso motivo: significherebbe vietare di guardare nell'intero albero sottostante,
    /// dove vivono percorsi legittimamente pulibili come "~/Downloads" o "~/progetti". La regola
    /// "/Users" resta invece una protezione ricorsiva mirata (le home degli ALTRI utenti, non la
    /// propria) e si applica anche qui. Usato da `PathGuard.validateRoot`;
    /// `PathGuard.validate` continua a usare `deniedReason` per intero, perché
    /// lì il percorso candidato è l'elemento da cancellare, non la root da cui si parte.
    func recursiveDeniedReason(_ canonicalPath: String?) -> String? {
        guard let path = CanonicalPath.canonical(canonicalPath) else {
            return String(localized: "percorso non canonico", bundle: .module)
        }

        for allowed in exceptions where PathText.isSameOrUnder(path, allowed) {
            return nil
        }

        return otherUsersReason(path) ?? recursiveReason(path)
    }

    /// "/Users" è protetto in blocco tranne il sottoalbero della home configurata: le home degli
    /// altri utenti del Mac non godono delle eccezioni di questo profilo.
    private func otherUsersReason(_ path: String) -> String? {
        guard PathText.isSameOrUnder(path, "/Users"), !PathText.isSameOrUnder(path, homeDirectory) else {
            return nil
        }
        return String(localized: "percorso protetto: /Users (home di un altro utente)", bundle: .module)
    }

    private func recursiveReason(_ path: String) -> String? {
        for entry in denied where PathText.isSameOrUnder(path, entry) {
            return String(localized: "percorso protetto: \(entry)", bundle: .module)
        }
        return nil
    }
}
