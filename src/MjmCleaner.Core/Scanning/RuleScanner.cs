using System.IO.Abstractions;
using System.IO.Enumeration;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Scanning;

/// <summary>Interpreta una singola regola. Non segue mai i collegamenti simbolici.</summary>
public sealed class RuleScanner(
    IFileSystem fileSystem,
    IPathGuard guard,
    ILinkInspector links,
    TimeProvider clock)
{
    public RuleScanOutcome Scan(CleanupRule rule, CancellationToken ct)
    {
        List<ScanItem> items = [];
        List<ScanError> errors = [];
        List<GuardExclusion> exclusions = [];

        // Root assente: categoria vuota, non errore.
        if (!fileSystem.Directory.Exists(rule.Root))
        {
            return new RuleScanOutcome(items, errors, exclusions);
        }

        // La root si valida una volta sola, e la validazione risale fino alla radice del
        // filesystem: se la root stessa o un suo antenato è un collegamento simbolico,
        // ogni elemento trovato sotto di essa punterebbe altrove. È il caso di chi sposta
        // ~/Library/Caches su un disco esterno con un collegamento.
        GuardVerdict rootVerdict = guard.ValidateRoot(rule.Root);
        if (!rootVerdict.IsAllowed)
        {
            exclusions.Add(new GuardExclusion(rule.Root, rootVerdict.Reason));
            return new RuleScanOutcome(items, errors, exclusions);
        }

        switch (rule.Mode)
        {
            case ScanMode.ClearContents:
                ScanContents(rule, items, errors, exclusions, ct);
                break;
            case ScanMode.MatchingFiles:
                ScanFiles(rule, rule.Root, depth: 0, items, errors, exclusions, ct);
                break;
            case ScanMode.MatchingDirs:
                ScanDirectories(rule, rule.Root, depth: 0, items, errors, exclusions, ct);
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(rule));
        }

        return new RuleScanOutcome(items, errors, exclusions);
    }

    private void ScanContents(
        CleanupRule rule,
        List<ScanItem> items,
        List<ScanError> errors,
        List<GuardExclusion> exclusions,
        CancellationToken ct)
    {
        foreach (string entry in Enumerate(rule.Root, errors))
        {
            ct.ThrowIfCancellationRequested();

            string name = fileSystem.Path.GetFileName(entry);
            if (!MatchesGlobs(name, rule))
            {
                continue;
            }

            // Il verdetto del guard precede qualunque lettura di statistiche (dimensione, età):
            // per una directory negata (es. "~/Library/Keychains"), calcolarle comunque
            // richiederebbe di attraversarla per intero, ed eventuali errori di lettura sui file
            // al suo interno — i cui percorsi possono essere privati — finirebbero nell'elenco
            // degli errori mostrato all'utente prima ancora che l'elemento risulti escluso.
            GuardVerdict verdict = guard.Validate(entry, rule.Root);
            if (!verdict.IsAllowed)
            {
                exclusions.Add(new GuardExclusion(entry, verdict.Reason));
                continue;
            }

            bool isLink = links.IsSymbolicLink(entry);
            bool isDirectory = !isLink && fileSystem.Directory.Exists(entry);
            long size;

            if (isLink)
            {
                // Non si attraversa mai il bersaglio per calcolarne la dimensione (resta 0). Il
                // filtro di età legge comunque l'inode tramite FileInfo/DirectoryInfo, che su
                // Unix seguono i collegamenti: il timestamp letto è quindi quello del bersaglio,
                // non quello del collegamento in sé.
                if (!Accept(entry, rule, isDirectoryCandidate: true, errors))
                {
                    continue;
                }

                size = 0;
            }
            else if (isDirectory)
            {
                // Età e dimensione nello stesso attraversamento: su disco vero l'mtime di una
                // directory non cambia quando un file al suo interno viene riscritto sul posto,
                // quindi il timestamp del solo contenitore è un segnale inaffidabile per l'età
                // del contenuto. Si usa invece il timestamp più recente trovato nell'albero.
                (long dirSize, DateTime newestUtc, bool determinable) = DirectoryStats(entry, errors, ct);
                if (!determinable)
                {
                    // Scomparsa o illeggibile fra l'enumerazione e questo punto: non va
                    // aggiunta agli elementi, altrimenti lo stesso percorso comparirebbe sia
                    // fra gli errori sia fra ciò che si propone di eliminare — la stessa
                    // deduplicazione già applicata ai file in TryFileSize.
                    continue;
                }

                if (!AcceptStamp(newestUtc, rule.MinAge))
                {
                    continue;
                }

                size = dirSize;
            }
            else
            {
                // Un file scomparso fra l'enumerazione e la lettura della dimensione va
                // annotato come errore, non aggiunto agli elementi con dimensione 0: altrimenti
                // lo stesso percorso comparirebbe sia fra gli errori sia fra ciò che si propone
                // di eliminare.
                if (!TryFileSize(entry, errors, out long fileSize))
                {
                    continue;
                }

                if (!Accept(entry, rule, isDirectoryCandidate: false, errors))
                {
                    continue;
                }

                size = fileSize;
            }

            if (rule.MinSizeBytes is { } minSize && size < minSize)
            {
                continue;
            }

            items.Add(new ScanItem(entry, size, isDirectory, rule.Root));
        }
    }

    private void ScanFiles(
        CleanupRule rule,
        string directory,
        int depth,
        List<ScanItem> items,
        List<ScanError> errors,
        List<GuardExclusion> exclusions,
        CancellationToken ct)
    {
        if (depth > rule.MaxDepth)
        {
            return;
        }

        foreach (string entry in Enumerate(directory, errors))
        {
            ct.ThrowIfCancellationRequested();

            if (links.IsSymbolicLink(entry))
            {
                continue;
            }

            if (fileSystem.Directory.Exists(entry))
            {
                // Pota il ramo intero invece di scendervi: un'esclusione per directory protetta
                // invece di una per ciascun file al suo interno, che altrimenti ne rivelerebbe i
                // nomi (es. dentro "~/Documents" o "~/.ssh") nell'elenco mostrato all'utente.
                // Solo la deny-list, non Validate: la regola di profondità di Validate
                // poterebbe ogni cartella legittima di primo livello sotto la home.
                if (guard.ShouldPrune(entry, out string pruneReason))
                {
                    exclusions.Add(new GuardExclusion(entry, pruneReason));
                    continue;
                }

                ScanFiles(rule, entry, depth + 1, items, errors, exclusions, ct);
                continue;
            }

            string name = fileSystem.Path.GetFileName(entry);
            if (!MatchesGlobs(name, rule) || !Accept(entry, rule, isDirectoryCandidate: false, errors))
            {
                continue;
            }

            if (!TryFileSize(entry, errors, out long size))
            {
                continue;
            }

            if (rule.MinSizeBytes is { } minSize && size < minSize)
            {
                continue;
            }

            GuardVerdict verdict = guard.Validate(entry, rule.Root);
            if (!verdict.IsAllowed)
            {
                exclusions.Add(new GuardExclusion(entry, verdict.Reason));
                continue;
            }

            items.Add(new ScanItem(entry, size, false, rule.Root));
        }
    }

    private static readonly string[] ProjectMarkers =
        ["*.csproj", "*.fsproj", "*.vbproj", "*.sln", "*.slnx"];

    /// <summary>
    /// Cerca ricorsivamente directory il cui nome corrisponde ai pattern (cartelle "bin"/"obj"
    /// nei progetti .NET, pacchetti NuGet inutilizzati). Una directory trovata non viene mai
    /// attraversata oltre: verrà eliminata per intero, quindi scendervi produrrebbe elementi
    /// annidati ridondanti.
    /// </summary>
    private void ScanDirectories(
        CleanupRule rule,
        string directory,
        int depth,
        List<ScanItem> items,
        List<ScanError> errors,
        List<GuardExclusion> exclusions,
        CancellationToken ct)
    {
        if (depth > rule.MaxDepth)
        {
            return;
        }

        foreach (string entry in Enumerate(directory, errors))
        {
            ct.ThrowIfCancellationRequested();

            if (links.IsSymbolicLink(entry) || !fileSystem.Directory.Exists(entry))
            {
                continue;
            }

            string name = fileSystem.Path.GetFileName(entry);

            if (MatchesAnyGlob(name, rule.ExcludeGlobs))
            {
                // Un'esclusione qui ha un significato diverso da "il nome non corrisponde a
                // nessun pattern di inclusione": è un rifiuto esplicito, non un "continua pure
                // a cercare più in basso". Trattarla come un semplice mancato match (proseguendo
                // la ricorsione al suo interno) proporrebbe una singola versione di un pacchetto
                // NuGet esplicitamente escluso invece del pacchetto intero — l'esito che questo
                // task esiste per impedire. Stessa semantica della potatura di un ramo negato
                // dalla deny-list: non si propone e non ci si scende dentro.
                continue;
            }

            bool matches = MatchesAnyGlob(name, rule.IncludeGlobs)
                           && (!rule.RequiresProjectMarker || HasProjectMarker(directory, errors));

            if (matches)
            {
                // Il verdetto del guard precede la lettura di dimensione ed età, come in
                // ScanContents: per una directory negata, calcolarle comunque richiederebbe di
                // attraversarla per intero (vedi il commento sopra la chiamata equivalente in
                // ScanContents).
                GuardVerdict verdict = guard.Validate(entry, rule.Root);
                if (!verdict.IsAllowed)
                {
                    exclusions.Add(new GuardExclusion(entry, verdict.Reason));
                    continue;
                }

                // Stesso attraversamento unico di ScanContents per una directory: dimensione ed
                // età più recente si leggono insieme, non con un secondo giro sull'albero.
                (long size, DateTime newestUtc, bool determinable) = DirectoryStats(entry, errors, ct);
                if (!determinable || !AcceptStamp(newestUtc, rule.MinAge))
                {
                    continue;
                }

                if (rule.MinSizeBytes is { } minSize && size < minSize)
                {
                    continue;
                }

                items.Add(new ScanItem(entry, size, true, rule.Root));

                // Trovata: non si scende oltre, l'intera cartella verrà eliminata.
                continue;
            }

            // Pota il ramo intero invece di scendervi, come ScanFiles: solo la deny-list, non
            // Validate, la cui regola di profondità poterebbe ogni cartella legittima di primo
            // livello sotto la home.
            if (guard.ShouldPrune(entry, out string pruneReason))
            {
                exclusions.Add(new GuardExclusion(entry, pruneReason));
                continue;
            }

            ScanDirectories(rule, entry, depth + 1, items, errors, exclusions, ct);
        }
    }

    /// <summary>
    /// Vera se la directory che contiene il candidato ospita un file di progetto. Senza questo
    /// vincolo una root mal configurata (es. "/" o "/usr") porterebbe a proporre l'eliminazione
    /// di cartelle come "/usr/bin": il PathGuard la bloccherebbe comunque, ma questo è il primo
    /// filtro.
    /// </summary>
    private bool HasProjectMarker(string parentDirectory, List<ScanError> errors)
    {
        foreach (string sibling in Enumerate(parentDirectory, errors))
        {
            // Un marcatore di progetto è sempre un file (".csproj", ".sln", ...): una
            // *directory* chiamata per esempio "x.sln" non deve poter soddisfare il vincolo,
            // altrimenti diventerebbe un modo in più per proporre l'eliminazione di una cartella
            // che il marcatore esiste apposta per proteggere.
            if (fileSystem.Directory.Exists(sibling))
            {
                continue;
            }

            string name = fileSystem.Path.GetFileName(sibling);

            foreach (string marker in ProjectMarkers)
            {
                if (FileSystemName.MatchesSimpleExpression(marker, name, ignoreCase: true))
                {
                    return true;
                }
            }
        }

        return false;
    }

    /// <summary>
    /// Applica il filtro di età leggendo il timestamp del percorso stesso (il più recente fra
    /// accesso e scrittura): usato per i file e per i collegamenti simbolici, mai per le
    /// directory in ClearContents, la cui età si calcola invece con <see cref="AcceptStamp"/>
    /// sul timestamp più recente trovato nell'albero.
    /// </summary>
    private bool Accept(string path, CleanupRule rule, bool isDirectoryCandidate, List<ScanError> errors)
    {
        if (rule.MinAge is not { } minAge)
        {
            return true;
        }

        try
        {
            IFileSystemInfo info = isDirectoryCandidate && fileSystem.Directory.Exists(path)
                ? fileSystem.DirectoryInfo.New(path)
                : fileSystem.FileInfo.New(path);

            DateTime stamp = info.LastAccessTimeUtc > info.LastWriteTimeUtc
                ? info.LastAccessTimeUtc
                : info.LastWriteTimeUtc;

            return AcceptStamp(stamp, minAge);
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            errors.Add(Describe(path, ex));
            return false;
        }
    }

    /// <summary>Applica il filtro di età a un timestamp già letto (es. il più recente trovato in un albero).</summary>
    private bool AcceptStamp(DateTime stampUtc, TimeSpan? minAge)
        => minAge is not { } age || clock.GetUtcNow().UtcDateTime - stampUtc >= age;

    private static bool MatchesGlobs(string name, CleanupRule rule)
        => !MatchesAnyGlob(name, rule.ExcludeGlobs) && MatchesAnyGlob(name, rule.IncludeGlobs);

    private static bool MatchesAnyGlob(string name, IReadOnlyList<string> globs)
    {
        foreach (string glob in globs)
        {
            if (FileSystemName.MatchesSimpleExpression(glob, name, ignoreCase: true))
            {
                return true;
            }
        }

        return false;
    }

    private IEnumerable<string> Enumerate(string directory, List<ScanError> errors)
    {
        try
        {
            return fileSystem.Directory.EnumerateFileSystemEntries(directory);
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            errors.Add(Describe(directory, ex));
            return [];
        }
    }

    /// <summary>
    /// Prima data considerata un vero timestamp anziché una sentinella: ben prima che questo
    /// progetto esistesse. Vedi <see cref="ReadDirectoryStampUtc"/>.
    /// </summary>
    private static readonly DateTime MinDeterminableStampUtc = new(1990, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    /// <summary>
    /// Calcola dimensione totale, timestamp più recente e determinabilità di una directory in un
    /// solo attraversamento (invece di due), saltando i collegamenti simbolici incontrati: non
    /// vanno mai attraversati, altrimenti la dimensione conteggerebbe due volte o uscirebbe
    /// dall'albero. Il timestamp della directory stessa è il valore di partenza (serve da
    /// riferimento per le directory vuote), poi si tiene il massimo con ogni figlio trovato.
    /// Il flag di determinabilità nel valore restituito riguarda solo il timestamp della
    /// directory passata come argomento, non dei suoi discendenti: una sottodirectory scomparsa
    /// durante la ricorsione non invalida l'intero risultato, contribuisce semplicemente 0 alla
    /// dimensione (Enumerate registra comunque il proprio errore) e non aggiorna il timestamp
    /// più recente.
    /// </summary>
    private (long Size, DateTime NewestUtc, bool Determinable) DirectoryStats(
        string directory, List<ScanError> errors, CancellationToken ct)
    {
        long total = 0;
        DateTime? ownStamp = ReadDirectoryStampUtc(directory, errors);
        DateTime newest = ownStamp ?? DateTime.MinValue;

        foreach (string entry in Enumerate(directory, errors))
        {
            ct.ThrowIfCancellationRequested();

            if (links.IsSymbolicLink(entry))
            {
                continue;
            }

            if (fileSystem.Directory.Exists(entry))
            {
                (long size, DateTime childNewest, _) = DirectoryStats(entry, errors, ct);
                total += size;
                if (childNewest > newest)
                {
                    newest = childNewest;
                }
            }
            else
            {
                (long size, DateTime stamp) = FileSizeAndStamp(entry, errors);
                total += size;
                if (stamp > newest)
                {
                    newest = stamp;
                }
            }
        }

        return (total, newest, ownStamp is not null);
    }

    /// <summary>
    /// Legge il timestamp più recente (fra accesso e scrittura) di una directory, o null se non
    /// è determinabile. Una directory scomparsa o illeggibile non sempre lancia un'eccezione:
    /// misurato sul filesystem reale, <c>DirectoryInfo.LastWriteTimeUtc</c>/<c>LastAccessTimeUtc</c>
    /// su un percorso inesistente non lanciano affatto — restituiscono la sentinella
    /// "1601-01-01", il valore più vecchio possibile, l'opposto di "indeterminato". Qualunque
    /// data precedente a <see cref="MinDeterminableStampUtc"/> è quindi trattata come sentinella,
    /// non come età reale (il controllo sull'eccezione resta comunque, come difesa in profondità
    /// per implementazioni di IFileSystem diverse da quella reale).
    /// </summary>
    private DateTime? ReadDirectoryStampUtc(string path, List<ScanError> errors)
    {
        try
        {
            IDirectoryInfo info = fileSystem.DirectoryInfo.New(path);
            DateTime stamp = info.LastAccessTimeUtc > info.LastWriteTimeUtc
                ? info.LastAccessTimeUtc
                : info.LastWriteTimeUtc;

            return stamp < MinDeterminableStampUtc ? null : stamp;
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            errors.Add(Describe(path, ex));
            return null;
        }
    }

    /// <summary>
    /// Legge dimensione e timestamp di un file in un solo accesso, per non registrare due
    /// errori distinti quando entrambe le letture fallirebbero per lo stesso motivo.
    /// </summary>
    private (long Size, DateTime StampUtc) FileSizeAndStamp(string path, List<ScanError> errors)
    {
        try
        {
            IFileInfo info = fileSystem.FileInfo.New(path);
            DateTime stamp = info.LastAccessTimeUtc > info.LastWriteTimeUtc
                ? info.LastAccessTimeUtc
                : info.LastWriteTimeUtc;

            return (info.Length, stamp);
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            errors.Add(Describe(path, ex));
            return (0, clock.GetUtcNow().UtcDateTime);
        }
    }

    /// <summary>
    /// Legge la dimensione di un file che diventerà esso stesso un elemento. A differenza di
    /// <see cref="FileSizeAndStamp"/> (usata per i figli sommati dentro una directory, mai
    /// esposti singolarmente), qui un fallimento "non trovato" deve impedire l'aggiunta
    /// dell'elemento: altrimenti lo stesso percorso comparirebbe sia fra gli errori sia fra ciò
    /// che si propone di eliminare.
    /// </summary>
    private bool TryFileSize(string path, List<ScanError> errors, out long size)
    {
        try
        {
            size = fileSystem.FileInfo.New(path).Length;
            return true;
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            ScanError error = Describe(path, ex);
            errors.Add(error);
            size = 0;
            return error.Kind != ScanErrorKind.NotFound;
        }
    }

    internal static bool IsExpected(Exception ex)
        => ex is UnauthorizedAccessException or IOException;

    internal static ScanError Describe(string path, Exception ex) => ex switch
    {
        UnauthorizedAccessException => new ScanError(path, ScanErrorKind.AccessDenied, ex.Message),
        FileNotFoundException or DirectoryNotFoundException => new ScanError(path, ScanErrorKind.NotFound, ex.Message),
        IOException io when io.Message.Contains("not empty", StringComparison.OrdinalIgnoreCase)
            => new ScanError(path, ScanErrorKind.NotEmpty, io.Message),
        IOException => new ScanError(path, ScanErrorKind.InUse, ex.Message),
        _ => new ScanError(path, ScanErrorKind.Other, ex.Message),
    };
}
