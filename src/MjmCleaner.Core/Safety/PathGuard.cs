namespace MjmCleaner.Core.Safety;

/// <summary>
/// Esito di una validazione. <see cref="CanonicalPathValidated"/> è il percorso su cui il
/// verdetto è stato effettivamente emesso: quando permesso, è quello che va eliminato, non
/// l'argomento originale passato a <see cref="IPathGuard.Validate"/> — validare una stringa e
/// cancellarne un'altra vanificherebbe ogni controllo precedente. È vuoto quando il verdetto è
/// un rifiuto emesso prima che un percorso canonico fosse disponibile (es. root non canonica).
/// </summary>
public sealed record GuardVerdict(bool IsAllowed, string Reason, string CanonicalPathValidated)
{
    public static GuardVerdict Allow(string canonicalPath) => new(true, string.Empty, canonicalPath);

    public static GuardVerdict Deny(string reason, string canonicalPath = "") => new(false, reason, canonicalPath);
}

public interface IPathGuard
{
    /// <summary>
    /// Valida la root dichiarata da una regola, risalendo i suoi antenati fino alla radice del
    /// filesystem: se la root stessa, o un suo qualsiasi antenato, è un collegamento simbolico,
    /// lo risolve alla destinazione finale invece di negarlo alla cieca (su macOS "/var", "/etc"
    /// e "/tmp" sono essi stessi collegamenti, quindi negare sempre renderebbe "$TMPDIR"
    /// permanentemente non pulibile), e applica al percorso risolto — che
    /// <see cref="GuardVerdict.CanonicalPathValidated"/> riporta — il controllo di canonicità e
    /// solo le voci RICORSIVE della deny-list (non quelle a uguaglianza esatta, che proteggono
    /// solo se stesse: applicarle a una root vieterebbe di guardare nell'intero albero
    /// sottostante, non solo di cancellare quel percorso). Nega comunque se la destinazione di
    /// un collegamento non è determinabile. Va invocata una volta per regola, prima di iterare
    /// sugli elementi che quella regola produce — non per ciascun elemento validato da
    /// <see cref="Validate"/>, che per ciascun elemento applica invece la deny-list per intero.
    /// </summary>
    GuardVerdict ValidateRoot(string declaredRoot);

    /// <summary>
    /// Valida un singolo elemento contro la root dichiarata dalla regola che l'ha prodotto.
    /// Presuppone che <see cref="ValidateRoot"/> sia già stata invocata con successo su quella
    /// stessa root: il ciclo sui collegamenti simbolici qui risale solo fino alla root, non oltre.
    /// </summary>
    GuardVerdict Validate(string candidatePath, string declaredRoot);

    /// <summary>
    /// Indica se una directory va esclusa dalla discesa ricorsiva perché la deny-list la
    /// protegge, così che uno scanner possa potare l'intero ramo invece di enumerarlo e
    /// produrre un'esclusione per ciascun elemento al suo interno (che, per percorsi come
    /// "~/Documents" o "~/.ssh", ne rivelerebbe i nomi dei file nell'elenco delle esclusioni
    /// mostrato all'utente). Applica solo la deny-list, non il contenimento né la regola di
    /// profondità di <see cref="Validate"/>: quest'ultima poterebbe ogni cartella legittima di
    /// primo livello sotto la home.
    /// </summary>
    bool ShouldPrune(string candidatePath, out string reason);
}

/// <summary>
/// Ultima linea di difesa: invocato immediatamente prima di ogni eliminazione, non solo
/// quando si definiscono le regole. Non lancia mai eccezioni: un input malformato produce un
/// rifiuto motivato, non un'eccezione che un <c>catch</c> a monte potrebbe trasformare in un
/// salto silenzioso.
/// </summary>
public sealed class PathGuard : IPathGuard
{
    private const StringComparison Cmp = StringComparison.OrdinalIgnoreCase;

    private readonly DenyList _denyList;
    private readonly ILinkInspector _links;
    private readonly string _home;

    public PathGuard(DenyList denyList, ILinkInspector links, string? homeDirectory)
    {
        ArgumentNullException.ThrowIfNull(denyList);
        ArgumentNullException.ThrowIfNull(links);

        if (!CanonicalPath.IsCanonical(homeDirectory, out string home) || home == "/")
        {
            throw new ArgumentException(
                "La home directory deve essere un percorso assoluto canonico diverso dalla radice.",
                nameof(homeDirectory));
        }

        // Imposta, non solo documenta: con due home diverse fra guard e deny-list, la regola
        // di profondità (punto 4 di Validate) proteggerebbe la home sbagliata.
        if (!home.Equals(denyList.HomeDirectory, Cmp))
        {
            throw new ArgumentException(
                "La home del PathGuard deve coincidere con quella della DenyList.",
                nameof(homeDirectory));
        }

        _denyList = denyList;
        _links = links;
        _home = home;
    }

    /// <summary>
    /// Limite di sostituzioni successive durante la risoluzione dei collegamenti di una root:
    /// una catena più lunga è quasi certamente un ciclo nel doppio di test, non uno scenario
    /// reale — nega invece di girare all'infinito.
    /// </summary>
    private const int MaxSymlinkResolutions = 32;

    public GuardVerdict ValidateRoot(string declaredRoot)
    {
        try
        {
            if (!TryCanonicalizeRoot(declaredRoot, out string root, out GuardVerdict? error))
            {
                return error!;
            }

            // Invece di negare non appena un antenato è un collegamento, lo risolve: su macOS
            // "/var" (quindi "$TMPDIR"), "/etc" e "/tmp" sono essi stessi collegamenti simbolici
            // verso "/private/...", quindi negare alla cieca renderebbe $TMPDIR permanentemente
            // non pulibile. Il percorso risolto è quello reale: gli va applicata la stessa
            // deny-list e lo stesso controllo di canonicità già usati altrove, non un'esenzione.
            if (!TryResolveSymlinkedAncestors(root, out string resolved, out GuardVerdict? resolutionError))
            {
                return resolutionError!;
            }

            // Due cause distinte, due messaggi distinti: un percorso risolto non canonico (per
            // esempio perché un collegamento fasullo punta a qualcosa di malformato) non
            // "coincide con la radice del filesystem" — lo fa solo il caso, verificato a parte,
            // in cui coincide letteralmente con "/".
            if (!CanonicalPath.IsCanonical(resolved, out string canonicalResolved))
            {
                return GuardVerdict.Deny("root risolta non canonica");
            }

            if (canonicalResolved == "/")
            {
                return GuardVerdict.Deny("root risolta degenere: coincide con la radice del filesystem");
            }

            // Solo le voci ricorsive della deny-list, non quelle a uguaglianza esatta ("/",
            // "/Users", la home): queste ultime proteggono solo se stesse, non il permesso di
            // guardarci dentro — applicarle qui vieterebbe di scansionare l'intero albero sotto
            // una root come la home stessa (es. "$TMPDIR" o "~" per LargeFileRoots), mentre gli
            // elementi individualmente protetti al suo interno restano negati da Validate.
            if (_denyList.IsDeniedRecursively(canonicalResolved, out string reason))
            {
                return GuardVerdict.Deny(reason, canonicalResolved);
            }

            return GuardVerdict.Allow(canonicalResolved);
        }
        catch (Exception ex) when (IsPathException(ex))
        {
            return GuardVerdict.Deny($"root non valida: {ex.Message}");
        }
    }

    /// <summary>
    /// Risolve iterativamente i collegamenti simbolici fra gli antenati di <paramref name="root"/>
    /// (se stessa inclusa), sostituendo ciascuno con la sua destinazione finale, finché non ne
    /// restano più. Se un antenato è un collegamento la cui destinazione non è determinabile,
    /// nega per sicurezza invece di proseguire alla cieca: non è una regressione, è lo stesso
    /// rifiuto che il codice precedente applicava a ogni antenato collegato, ora ristretto ai
    /// soli casi realmente irrisolvibili.
    /// </summary>
    private bool TryResolveSymlinkedAncestors(string root, out string resolved, out GuardVerdict? error)
    {
        string current = root;

        for (int iteration = 0; iteration < MaxSymlinkResolutions; iteration++)
        {
            string? substituted = null;

            for (string? ancestor = current; ancestor is not null; ancestor = Path.GetDirectoryName(ancestor))
            {
                if (!_links.IsSymbolicLink(ancestor))
                {
                    continue;
                }

                string? target = _links.ResolveLinkTarget(ancestor);
                if (target is null)
                {
                    resolved = string.Empty;
                    error = GuardVerdict.Deny(
                        $"la root o un suo antenato è un collegamento simbolico la cui destinazione non è determinabile: {ancestor}",
                        current);
                    return false;
                }

                string suffix = current.Length > ancestor.Length ? current[ancestor.Length..] : string.Empty;
                substituted = target.TrimEnd('/') + suffix;
                break;
            }

            if (substituted is null)
            {
                resolved = current;
                error = null;
                return true;
            }

            current = substituted;
        }

        resolved = string.Empty;
        error = GuardVerdict.Deny($"troppi collegamenti simbolici annidati mentre si risolveva la root: {root}");
        return false;
    }

    public bool ShouldPrune(string candidatePath, out string reason)
    {
        if (!CanonicalPath.IsCanonical(candidatePath, out string path))
        {
            reason = "percorso non canonico";
            return true;
        }

        return _denyList.IsDenied(path, out reason);
    }

    public GuardVerdict Validate(string candidatePath, string declaredRoot)
    {
        try
        {
            // 1. Rifiuto dei percorsi non canonici, prima di qualsiasi confronto. Nessuna
            //    risoluzione testuale di "." o "..": un collegamento simbolico seguito da ".."
            //    verrebbe risolto dal kernel *dopo* aver attraversato il collegamento, mentre
            //    una risoluzione testuale lo risolverebbe *prima*, facendo sparire il
            //    collegamento dalla stringa prima che la regola 5 possa vederlo. Gli elementi
            //    da eliminare arrivano sempre dall'enumerazione del filesystem, che non
            //    produce mai "..": il rifiuto non toglie nulla di legittimo.
            if (!CanonicalPath.IsCanonical(candidatePath, out string path))
            {
                return GuardVerdict.Deny("percorso non canonico");
            }

            if (!TryCanonicalizeRoot(declaredRoot, out string root, out GuardVerdict? error))
            {
                return error!;
            }

            // 2. Contenimento nella root dichiarata dalla regola che ha prodotto l'elemento.
            if (!path.StartsWith(root + "/", Cmp) && !path.Equals(root, Cmp))
            {
                return GuardVerdict.Deny($"violazione del contenimento: fuori da {root}", path);
            }

            // 3. Deny-list.
            if (_denyList.IsDenied(path, out string reason))
            {
                return GuardVerdict.Deny(reason, path);
            }

            // 4. Profondità minima: mai la home, mai un suo figlio diretto.
            if (IsHomeOrDirectChild(path))
            {
                return GuardVerdict.Deny("profondità insufficiente: figlio diretto della home", path);
            }

            // 5. Collegamenti simbolici fra l'elemento e la root: la root stessa e tutto ciò
            //    che sta sopra sono già stati verificati da ValidateRoot, quindi qui basta
            //    risalire fino a lì, non oltre.
            for (string? ancestor = Path.GetDirectoryName(path);
                 ancestor is not null && ancestor.Length > root.Length;
                 ancestor = Path.GetDirectoryName(ancestor))
            {
                if (_links.IsSymbolicLink(ancestor))
                {
                    return GuardVerdict.Deny($"antenato è un collegamento simbolico: {ancestor}", path);
                }
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
            if (path.Equals(root, Cmp))
            {
                return GuardVerdict.Deny($"l'elemento coincide con la root della regola: {root}", path);
            }

            return GuardVerdict.Allow(path);
        }
        catch (Exception ex) when (IsPathException(ex))
        {
            return GuardVerdict.Deny($"percorso non valido: {ex.Message}");
        }
    }

    /// <summary>
    /// Canonicalizza la root e ne rifiuta le forme degeneri: una root che, dopo la
    /// canonicalizzazione, coincide con la radice del filesystem rende il contenimento
    /// (punto 2 di <see cref="Validate"/>) vero per qualunque percorso assoluto ("comincia
    /// per /"), quindi privo di significato.
    /// </summary>
    private static bool TryCanonicalizeRoot(string declaredRoot, out string root, out GuardVerdict? error)
    {
        if (!CanonicalPath.IsCanonical(declaredRoot, out string canonical) || canonical == "/")
        {
            root = string.Empty;
            error = GuardVerdict.Deny("root non canonica o degenere: coincide con la radice del filesystem");
            return false;
        }

        root = canonical;
        error = null;
        return true;
    }

    private static bool IsPathException(Exception ex)
        => ex is ArgumentException or PathTooLongException or NotSupportedException or IOException;

    private bool IsHomeOrDirectChild(string path)
    {
        if (path.Equals(_home, Cmp))
        {
            return true;
        }

        if (!path.StartsWith(_home + "/", Cmp))
        {
            return false;
        }

        string relative = path[(_home.Length + 1)..];
        return !relative.Contains('/');
    }
}
