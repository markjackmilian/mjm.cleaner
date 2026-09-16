namespace MjmCleaner.Core.Safety;

/// <summary>
/// Percorsi che non devono mai essere eliminati. Non configurabile dall'interfaccia:
/// è l'ultima linea di difesa, non una preferenza.
/// </summary>
public sealed class DenyList
{
    private const StringComparison Cmp = StringComparison.OrdinalIgnoreCase;

    private readonly string _home;
    private readonly string[] _deniedExact;
    private readonly string[] _denied;
    private readonly string[] _exceptions;

    public DenyList(string? homeDirectory)
    {
        if (string.IsNullOrEmpty(homeDirectory) || homeDirectory[0] != '/' || homeDirectory == "/")
        {
            throw new ArgumentException(
                "La home directory deve essere un percorso assoluto diverso dalla radice.",
                nameof(homeDirectory));
        }

        string home = homeDirectory.TrimEnd('/');

        // Validato DOPO la normalizzazione, non prima: un argomento come "//" supera indisturbato
        // il controllo sul valore grezzo qui sopra (non è né vuoto né "/"), ma TrimEnd('/') lo
        // riduce a "" — a quel punto _home smette di essere un confine e la regola su "/Users"
        // si autoannulla, perché IsSameOrUnder(path, "") è vero per qualunque percorso assoluto.
        // "/Users" grezzo degenera la stessa regola allo stesso modo.
        if (home.Length == 0 || home.Equals("/Users", Cmp))
        {
            throw new ArgumentException(
                "La home directory deve restare un percorso assoluto non degenere, e diverso da \"/Users\", dopo la normalizzazione.",
                nameof(homeDirectory));
        }

        _home = home;

        // Uguaglianza esatta: proteggono solo se stesse, non un intero sottoalbero.
        // Un confronto ricorsivo su "/" o "/Users" negherebbe rispettivamente l'intero
        // filesystem o l'intera home di ogni utente, incluse le eccezioni sotto la home
        // dell'utente corrente — lo stesso difetto già corretto per la sola home.
        _deniedExact =
        [
            "/",
            "/Users",
            home,
        ];

        _denied =
        [
            "/System", "/usr", "/bin", "/sbin", "/etc", "/Applications", "/Library",
            "/Volumes", "/private/etc", "/private/var/db", "/private/var/root", "/Network", "/cores", "/opt",
            $"{home}/Documents",
            $"{home}/Desktop",
            $"{home}/Pictures",
            $"{home}/Movies",
            $"{home}/Music",
            $"{home}/Library/Application Support",
            $"{home}/Library/Mobile Documents",
            // Da macOS 12, OneDrive, Dropbox e Google Drive montano qui i documenti
            // dell'utente: proteggere iCloud (Mobile Documents) e non questi sarebbe
            // un'asimmetria arbitraria che costa dati.
            $"{home}/Library/CloudStorage",
            $"{home}/Library/Keychains",
            // Solo la sottocartella con le identità di firma e i profili di provisioning:
            // "Library/Developer" resta pulibile (DerivedData, Archives sono categorie
            // dell'app), quindi non va negato in blocco.
            $"{home}/Library/Developer/Xcode/UserData",
            $"{home}/.ssh",
            $"{home}/.gnupg",
            // Deve restare prima della voce "Containers" in blocco qui sotto: essendo più
            // specifica, vince nel ciclo e la motivazione restituita nomina Docker invece
            // della cartella generica.
            $"{home}/Library/Containers/com.docker.docker",
            $"{home}/Library/Messages",
            $"{home}/Library/Mail",
            $"{home}/Library/Safari",
            $"{home}/Library/Preferences",
            $"{home}/Library/Group Containers",
            $"{home}/Library/Application Scripts",
            $"{home}/Library/Containers",
            $"{home}/.aws",
            $"{home}/.kube",
            $"{home}/.docker",
            $"{home}/.config",
            $"{home}/.password-store",
            $"{home}/.local",
            $"{home}/Applications",
            $"{home}/Public",
            $"{home}/Sites",
        ];

        _exceptions =
        [
            "/Library/Caches",
            "/Library/Logs",
        ];
    }

    /// <summary>
    /// La home configurata, normalizzata (assoluta, senza "/" finale). Espone lo stesso valore
    /// usato internamente per le regole, così che <see cref="PathGuard"/> possa verificare, al
    /// proprio costruttore, di riferirsi alla stessa home: due home diverse fra guard e
    /// deny-list proteggerebbero la home sbagliata.
    /// </summary>
    public string HomeDirectory => _home;

    /// <summary>
    /// Il percorso deve essere già canonicalizzato (vedi PathGuard). Il contratto viene fatto
    /// rispettare, non solo dichiarato: un percorso nullo, vuoto, relativo o non canonico
    /// (contiene "//", "/./", "/.." oppure termina con "/." o "/..") viene negato per sicurezza
    /// (fail-closed), perché altrimenti potrebbe scavalcare le eccezioni e i controlli sottostanti.
    /// </summary>
    public bool IsDenied(string? canonicalPath, out string reason)
    {
        if (!CanonicalPath.IsCanonical(canonicalPath, out string path))
        {
            reason = "percorso non canonico";
            return true;
        }

        foreach (string allowed in _exceptions)
        {
            if (IsSameOrUnder(path, allowed))
            {
                reason = string.Empty;
                return false;
            }
        }

        foreach (string exact in _deniedExact)
        {
            if (path.Equals(exact, Cmp))
            {
                reason = $"percorso protetto: {exact}";
                return true;
            }
        }

        // "/Users" è protetto in blocco tranne il sottoalbero della home configurata: le home
        // degli altri utenti del Mac non godono delle eccezioni di questo profilo e vanno
        // negate per intero, senza riprodurre a un livello più in alto lo stesso difetto già
        // corretto per la home dell'utente corrente.
        if (IsSameOrUnder(path, "/Users") && !IsSameOrUnder(path, _home))
        {
            reason = "percorso protetto: /Users (home di un altro utente)";
            return true;
        }

        foreach (string denied in _denied)
        {
            if (IsSameOrUnder(path, denied))
            {
                reason = $"percorso protetto: {denied}";
                return true;
            }
        }

        reason = string.Empty;
        return false;
    }

    private static bool IsSameOrUnder(string path, string ancestor)
        => path.Equals(ancestor, Cmp)
           || path.StartsWith(ancestor + "/", Cmp);
}
