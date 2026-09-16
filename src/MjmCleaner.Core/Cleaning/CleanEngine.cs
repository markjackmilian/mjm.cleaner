using System.Diagnostics;
using System.IO.Abstractions;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Cleaning;

public interface ICleanEngine
{
    Task<CleanReport> CleanAsync(
        IReadOnlyList<CategorySelection> selections,
        IProgress<CleanProgress>? progress,
        CancellationToken ct);
}

/// <summary>
/// Eliminazione definitiva. Sequenziale: su un singolo volume il parallelismo non
/// accelera e renderebbe il resoconto meno prevedibile.
/// </summary>
public sealed class CleanEngine(IFileSystem fileSystem, IPathGuard guard, TimeProvider clock)
    : ICleanEngine
{
    public Task<CleanReport> CleanAsync(
        IReadOnlyList<CategorySelection> selections,
        IProgress<CleanProgress>? progress,
        CancellationToken ct)
        => Task.Run(() => Clean(selections, progress, ct), CancellationToken.None);

    private CleanReport Clean(
        IReadOnlyList<CategorySelection> selections,
        IProgress<CleanProgress>? progress,
        CancellationToken ct)
    {
        DateTimeOffset startedAt = clock.GetUtcNow();
        long stamp = Stopwatch.GetTimestamp();

        List<CategoryCleanResult> categories = [];
        List<ScanError> errors = [];
        List<string> deleted = [];
        long totalBytes = 0;
        int totalDeleted = 0;
        int totalFailed = 0;
        int done = 0;
        int total = selections.Sum(s => s.Items.Count);
        string lastSeenPath = string.Empty;

        // Trova (o crea) la voce di categoria per un identificativo e vi accumula byte/conteggio:
        // due CategorySelection con lo stesso CategoryId devono confluire in un'unica voce del
        // resoconto, non in due, altrimenti un consumatore che cerca la categoria per
        // identificativo (lo stesso pattern usato dai test) riceverebbe un'eccezione.
        void AddToCategory(string categoryId, long bytesFreed, int itemsDeleted)
        {
            int index = categories.FindIndex(c => c.CategoryId == categoryId);
            if (index >= 0)
            {
                CategoryCleanResult existing = categories[index];
                categories[index] = existing with
                {
                    BytesFreed = existing.BytesFreed + bytesFreed,
                    ItemsDeleted = existing.ItemsDeleted + itemsDeleted,
                };
            }
            else
            {
                categories.Add(new CategoryCleanResult(categoryId, bytesFreed, itemsDeleted));
            }
        }

        // Un'eccezione inattesa (fuori dal contratto di RuleScanner.IsExpected, catturato per
        // ciascun elemento più sotto) non deve far propagare l'errore e perdere il resoconto:
        // per un'app che cancella senza Cestino, l'elenco di ciò che è già stato eliminato prima
        // del crash è l'unica ricostruzione possibile di cosa è sparito. Meglio un resoconto con
        // un errore ignoto che nessun resoconto.
        try
        {
            // Ultima linea di difesa: ogni DeclaredRoot distinta va validata con ValidateRoot,
            // una volta sola, PRIMA di considerare i singoli elementi. Validate da sola presuppone
            // che ValidateRoot sia già stata invocata con successo sulla stessa root: il suo
            // controllo sui collegamenti simbolici risale solo fino alla root (si ferma quando
            // "ancestor.Length > root.Length"), quindi quando la root è il genitore diretto
            // dell'elemento — il caso di OGNI regola ClearContents del catalogo — quel ciclo non
            // esegue nemmeno un'iterazione e un collegamento sulla root stessa passerebbe
            // inosservato. L'elenco arriva dall'interfaccia dopo la conferma dell'utente (quindi
            // manipolabile) e comunque può essere scaduto (root sostituita da un collegamento fra
            // la scansione e la conferma): richiamare ValidateRoot qui è la sola difesa per
            // entrambi i casi.
            Dictionary<string, GuardVerdict> rootVerdicts = new(StringComparer.OrdinalIgnoreCase);
            foreach (string declaredRoot in selections
                         .SelectMany(s => s.Items)
                         .Select(i => i.DeclaredRoot)
                         .Distinct(StringComparer.OrdinalIgnoreCase))
            {
                // Una root dichiarata nulla (elemento malformato) non può essere indicizzata:
                // Dictionary<string, _> rifiuta una chiave nulla lanciando ArgumentNullException,
                // fuori da ogni isolamento per elemento — il ciclo qui gira una volta sola per
                // TUTTE le root, non per elemento, quindi quel lancio farebbe fallire l'intera
                // pulizia invece del solo elemento che dichiara la root nulla. Va saltata qui; il
                // ciclo di eliminazione più sotto la tratta come root mancante per ciascun
                // elemento che la dichiara, isolando il fallimento a quegli elementi soltanto.
                if (declaredRoot is null)
                {
                    continue;
                }

                rootVerdicts[declaredRoot] = guard.ValidateRoot(declaredRoot);
            }

            foreach (CategorySelection selection in selections)
            {
                // L'annullamento restituisce un resoconto parziale: ciò che è già stato eliminato
                // deve comunque finire nello storico. Una categoria non ancora iniziata non va
                // aggiunta al resoconto con valori a zero: solo quelle effettivamente elaborate.
                if (ct.IsCancellationRequested)
                {
                    break;
                }

                if (categories.FindIndex(c => c.CategoryId == selection.CategoryId) < 0)
                {
                    categories.Add(new CategoryCleanResult(selection.CategoryId, 0, 0));
                }

                foreach (ScanItem item in selection.Items)
                {
                    if (ct.IsCancellationRequested)
                    {
                        break;
                    }

                    done++;
                    lastSeenPath = item.Path;

                    // Root mancante (elemento con DeclaredRoot nulla, isolata sopra) o negata: in
                    // entrambi i casi solo QUESTO elemento fallisce, non l'intera pulizia. Il
                    // controllo su declaredRoot è separato (invece di un unico "rootVerdict is
                    // null || ...") perché una variabile locale ristretta con un continue
                    // incondizionato resta non nulla per il resto del blocco, mentre un accesso a
                    // proprietà (item.DeclaredRoot) non lo sarebbe.
                    string? declaredRoot = item.DeclaredRoot;
                    if (declaredRoot is null)
                    {
                        errors.Add(new ScanError(item.Path, ScanErrorKind.Other, "root dichiarata mancante"));
                        totalFailed++;
                        progress?.Report(new CleanProgress(item.Path, done, total, totalBytes));
                        continue;
                    }

                    if (!rootVerdicts.TryGetValue(declaredRoot, out GuardVerdict? rootVerdict)
                        || !rootVerdict.IsAllowed)
                    {
                        string rootReason = rootVerdict?.Reason ?? "root dichiarata non riconosciuta";
                        errors.Add(new ScanError(item.Path, ScanErrorKind.Other, rootReason));
                        totalFailed++;
                        progress?.Report(new CleanProgress(item.Path, done, total, totalBytes));
                        continue;
                    }

                    // RuleScanner enumera a partire dalla root DICHIARATA: item.Path è quindi nel
                    // suo stesso sistema di riferimento non risolto, mentre ValidateRoot può aver
                    // risolto la root a una stringa diversa (es. $TMPDIR: "/var" è un collegamento
                    // a "/private/var" su ogni macOS di serie). Va riportato nel sistema di
                    // riferimento RISOLTO PRIMA di validarlo: altrimenti il contenimento
                    // confronterebbe due basi diverse e fallirebbe sempre, negando ogni elemento
                    // di ogni root la cui risoluzione cambia la stringa. Riscrivere DOPO la
                    // validazione reintrodurrebbe il difetto originario: prima si riscrive, poi si
                    // valida, poi si cancella il percorso che il guard restituisce.
                    string resolvedRoot = rootVerdict.CanonicalPathValidated;
                    string rewrittenPath = RewriteToResolvedRoot(item.Path, declaredRoot, resolvedRoot);

                    // Il contenimento (e il limite della risalita sui collegamenti simbolici) va
                    // verificato contro il percorso RISOLTO della root, non contro quello
                    // dichiarato: se la root risolve altrove, l'elemento non le appartiene più. È
                    // il passaggio che chiude la fuga per una root fabbricata o rilocata.
                    GuardVerdict verdict = guard.Validate(rewrittenPath, resolvedRoot);
                    if (!verdict.IsAllowed)
                    {
                        errors.Add(new ScanError(item.Path, ScanErrorKind.Other, verdict.Reason));
                        totalFailed++;
                        progress?.Report(new CleanProgress(item.Path, done, total, totalBytes));
                        continue;
                    }

                    // Si elimina il percorso che il guard ha VALIDATO, non quello di partenza:
                    // validare una stringa e cancellarne un'altra è il difetto che renderebbe
                    // aggirabile ogni controllo a monte.
                    string target = verdict.CanonicalPathValidated;

                    try
                    {
                        // Si contano solo i byte davvero liberati: la dimensione dichiarata
                        // dall'elemento arriva dall'interfaccia e non va fidata. Rilettura
                        // immediatamente prima della cancellazione, non prima: il suo costo è
                        // marginale rispetto alla cancellazione ricorsiva che segue comunque.
                        long size = MeasureRealSize(target, item.IsDirectory);

                        if (item.IsDirectory)
                        {
                            fileSystem.Directory.Delete(target, recursive: true);
                        }
                        else
                        {
                            if (!fileSystem.File.Exists(target))
                            {
                                throw new FileNotFoundException("elemento non più presente", target);
                            }

                            fileSystem.File.Delete(target);
                        }

                        totalBytes += size;
                        totalDeleted++;
                        deleted.Add(target);
                        AddToCategory(selection.CategoryId, size, 1);
                    }
                    catch (Exception ex) when (RuleScanner.IsExpected(ex))
                    {
                        errors.Add(RuleScanner.Describe(item.Path, ex));
                        totalFailed++;
                    }

                    progress?.Report(new CleanProgress(item.Path, done, total, totalBytes));
                }
            }
        }
        catch (Exception ex)
        {
            errors.Add(new ScanError(lastSeenPath, ScanErrorKind.Other, ex.Message));
            totalFailed++;
        }

        return new CleanReport(
            startedAt,
            Stopwatch.GetElapsedTime(stamp),
            totalBytes,
            totalDeleted,
            totalFailed,
            categories,
            errors,
            deleted);
    }

    /// <summary>
    /// Riporta <paramref name="path"/> dal sistema di riferimento della root DICHIARATA a quello
    /// della sua risoluzione, sostituendo il prefisso corrispondente. Se <paramref name="path"/>
    /// non inizia con <paramref name="declaredRoot"/> (confine di segmento, senza distinzione fra
    /// maiuscole e minuscole), non c'è nulla da riscrivere: non è comunque contenuto nella root
    /// dichiarata, e <c>Validate</c> lo rileverà confrontando il percorso invariato con quella
    /// risolta.
    /// </summary>
    private static string RewriteToResolvedRoot(string path, string declaredRoot, string resolvedRoot)
    {
        if (declaredRoot.Equals(resolvedRoot, StringComparison.OrdinalIgnoreCase))
        {
            return path;
        }

        if (path.Equals(declaredRoot, StringComparison.OrdinalIgnoreCase))
        {
            return resolvedRoot;
        }

        if (path.StartsWith(declaredRoot + "/", StringComparison.OrdinalIgnoreCase))
        {
            return resolvedRoot + path[declaredRoot.Length..];
        }

        return path;
    }

    /// <summary>
    /// Dimensione reale di un elemento, letta immediatamente prima di cancellarlo: mai quella
    /// dichiarata da <see cref="ScanItem.SizeBytes"/>, che arriva dall'interfaccia e non va
    /// fidata. Se la lettura fallisce, conta zero byte per quell'elemento invece di propagare
    /// l'errore qui: il tentativo di cancellazione che segue subito dopo lo registrerà comunque,
    /// con la classificazione corretta.
    /// </summary>
    private long MeasureRealSize(string path, bool isDirectory)
    {
        try
        {
            return isDirectory
                ? fileSystem.Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories)
                    .Sum(file => fileSystem.FileInfo.New(file).Length)
                : fileSystem.FileInfo.New(path).Length;
        }
        catch (Exception ex) when (RuleScanner.IsExpected(ex))
        {
            return 0;
        }
    }
}
