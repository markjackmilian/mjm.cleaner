using System.Diagnostics;

namespace MjmCleaner.Core.Diagnostics;

public interface IRunningAppsProbe
{
    IReadOnlyList<string> AffectedApps(IEnumerable<string> paths);
}

/// <summary>
/// Euristica: svuotare la cache di un'applicazione aperta può farla comportare in modo
/// anomalo fino al riavvio, quindi conviene avvisare prima di eliminare.
/// </summary>
public sealed class RunningAppsProbe(Func<IReadOnlyList<string>> processNames) : IRunningAppsProbe
{
    private const int MinimumWordLength = 4;
    private static readonly char[] WordSeparators = ['.', ' ', '-', '_'];

    public IReadOnlyList<string> AffectedApps(IEnumerable<string> paths)
    {
        (string FullName, string[] SignificantWords)[] candidates = [.. processNames()
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(name => (FullName: name, SignificantWords: SplitIntoWords(name)
                .Where(word => word.Length >= MinimumWordLength)
                .ToArray()))
            .Where(candidate => candidate.SignificantWords.Length > 0)];

        if (candidates.Length == 0)
        {
            return [];
        }

        HashSet<string> folderWords = new(StringComparer.OrdinalIgnoreCase);

        foreach (string path in paths)
        {
            foreach (string word in SplitIntoWords(Path.GetFileName(path)))
            {
                folderWords.Add(word);
            }
        }

        HashSet<string> affected = new(StringComparer.OrdinalIgnoreCase);

        foreach ((string fullName, string[] significantWords) in candidates)
        {
            if (significantWords.Any(folderWords.Contains))
            {
                affected.Add(fullName);
            }
        }

        return [.. affected.Order(StringComparer.OrdinalIgnoreCase)];
    }

    /// <summary>
    /// Scompone un nome (di processo o di cartella) nelle sue parole, usando come separatori
    /// il punto, lo spazio, il trattino e il trattino basso, così da confrontare parole intere
    /// invece di semplici sottostringhe (es. "Dock" non deve corrispondere a "com.docker.docker").
    /// </summary>
    private static string[] SplitIntoWords(string value)
        => value.Split(WordSeparators, StringSplitOptions.RemoveEmptyEntries);

    // --- Raccolta dei nomi sulla macchina reale --------------------------------------------
    //
    // Process.GetProcesses().ProcessName restituisce solo il nome breve del processo (es.
    // "accountsd", "ControlCenter"), perdendo il percorso: l'informazione che davvero conta
    // non è "il nome del processo assomiglia al nome della cartella", ma "questo processo è
    // un'applicazione che l'utente può chiudere". Un demone di sistema non è chiudibile e la
    // sua cache si rigenera senza conseguenze visibili, quindi avvisarne è rumore, non segnale.
    //
    // Chiediamo perciò a `ps` il percorso completo dell'eseguibile di ogni processo e teniamo
    // solo quelli che vivono dentro un bundle .app installato in /Applications,
    // /System/Applications o sotto la home dell'utente — non, per esempio, sotto
    // /System/Library, dove vivono agenti di sistema che pure hanno un bundle .app
    // (ControlCenter, WiFiAgent, loginwindow) ma che l'utente non percepisce come "un'app aperta".

    private const string BundleMarker = ".app/";
    private const string ExecutableMarker = ".app/Contents/MacOS/";
    private const int PsTimeoutMilliseconds = 5000;

    public static RunningAppsProbe ForCurrentMachine()
        => new(() => ExtractApplicationNames(CollectProcessPaths()));

    /// <summary>
    /// Ricava i nomi delle applicazioni utente dai percorsi completi dei processi in esecuzione
    /// (nella forma restituita da <c>ps -axo comm=</c>). Tiene solo i percorsi dentro un bundle
    /// .app installato in /Applications, /System/Applications o sotto la home dell'utente, e per
    /// ciascuno riporta il nome del primo bundle .app che compare nel percorso — quello
    /// dell'applicazione visibile all'utente, non quello di un eventuale sotto-processo
    /// Helper/Renderer annidato più in profondità (es. ".../Claude.app/Contents/Frameworks/
    /// Claude Helper.app/Contents/MacOS/Claude Helper" → "Claude").
    /// Esposto come metodo pubblico e puro (nessuna chiamata al sistema) per essere testabile
    /// direttamente, separato dalla raccolta effettiva dei processi in <see cref="CollectProcessPaths"/>.
    /// </summary>
    public static IReadOnlyList<string> ExtractApplicationNames(IEnumerable<string> processPaths)
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile).TrimEnd('/');
        string[] allowedRoots = ["/Applications/", "/System/Applications/", home + "/"];

        HashSet<string> names = new(StringComparer.OrdinalIgnoreCase);

        foreach (string path in processPaths)
        {
            if (string.IsNullOrWhiteSpace(path)
                || !path.Contains(ExecutableMarker, StringComparison.Ordinal)
                || !allowedRoots.Any(root => path.StartsWith(root, StringComparison.Ordinal)))
            {
                continue;
            }

            string? bundleName = FirstBundleName(path);

            if (bundleName is not null)
            {
                names.Add(bundleName);
            }
        }

        return [.. names];
    }

    private static string? FirstBundleName(string path)
    {
        int bundleIndex = path.IndexOf(BundleMarker, StringComparison.Ordinal);

        if (bundleIndex < 0)
        {
            return null;
        }

        string beforeBundle = path[..bundleIndex];
        int lastSeparator = beforeBundle.LastIndexOf('/');
        string name = lastSeparator >= 0 ? beforeBundle[(lastSeparator + 1)..] : beforeBundle;

        return string.IsNullOrEmpty(name) ? null : name;
    }

    /// <summary>
    /// Isolata dal resto: è l'unico punto che dipende da un comando esterno. Un avviso che non
    /// si può calcolare non deve mai impedire una pulizia, quindi qualunque fallimento
    /// (comando assente, permessi, timeout, processo che non risponde) restituisce un elenco
    /// vuoto invece di propagare l'errore.
    /// </summary>
    private static IReadOnlyList<string> CollectProcessPaths()
    {
        try
        {
            using Process process = new()
            {
                StartInfo = new ProcessStartInfo("ps", "-axo comm=")
                {
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                },
            };

            if (!process.Start())
            {
                return [];
            }

            Task<string> standardOutput = process.StandardOutput.ReadToEndAsync();
            Task<string> standardError = process.StandardError.ReadToEndAsync();

            bool completed = Task.WaitAll([standardOutput, standardError], PsTimeoutMilliseconds)
                && process.WaitForExit(PsTimeoutMilliseconds);

            if (!completed)
            {
                TryKill(process);
                return [];
            }

            return process.ExitCode == 0
                ? standardOutput.Result.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                : [];
        }
        catch
        {
            return [];
        }
    }

    private static void TryKill(Process process)
    {
        try
        {
            process.Kill(entireProcessTree: true);
        }
        catch
        {
            // Il processo può essere già terminato tra il timeout e il kill: non è un errore.
        }
    }
}
