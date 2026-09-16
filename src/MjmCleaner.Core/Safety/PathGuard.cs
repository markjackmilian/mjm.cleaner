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
    /// filesystem: nega se la root stessa, o un suo qualsiasi antenato, è un collegamento
    /// simbolico. Va invocata una volta per regola, prima di iterare sugli elementi che quella
    /// regola produce — non per ciascun elemento validato da <see cref="Validate"/>.
    /// </summary>
    GuardVerdict ValidateRoot(string declaredRoot);

    /// <summary>
    /// Valida un singolo elemento contro la root dichiarata dalla regola che l'ha prodotto.
    /// Presuppone che <see cref="ValidateRoot"/> sia già stata invocata con successo su quella
    /// stessa root: il ciclo sui collegamenti simbolici qui risale solo fino alla root, non oltre.
    /// </summary>
    GuardVerdict Validate(string candidatePath, string declaredRoot);
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

    public GuardVerdict ValidateRoot(string declaredRoot)
    {
        try
        {
            if (!TryCanonicalizeRoot(declaredRoot, out string root, out GuardVerdict? error))
            {
                return error!;
            }

            // Risale fino alla radice del filesystem (non solo fino alla home): una root può
            // essere un collegamento anche quando la home non lo è, e viceversa.
            for (string? ancestor = root; ancestor is not null; ancestor = Path.GetDirectoryName(ancestor))
            {
                if (_links.IsSymbolicLink(ancestor))
                {
                    return GuardVerdict.Deny(
                        $"la root o un suo antenato è un collegamento simbolico: {ancestor}",
                        root);
                }
            }

            return GuardVerdict.Allow(root);
        }
        catch (Exception ex) when (IsPathException(ex))
        {
            return GuardVerdict.Deny($"root non valida: {ex.Message}");
        }
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
