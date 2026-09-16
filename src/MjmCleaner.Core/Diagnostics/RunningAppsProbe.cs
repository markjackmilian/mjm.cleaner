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

    public static RunningAppsProbe ForCurrentMachine()
        => new(() =>
        {
            try
            {
                return [.. Process.GetProcesses().Select(p => p.ProcessName)];
            }
            catch
            {
                // Un avviso che non si può calcolare non deve impedire una pulizia: qualunque
                // fallimento nell'enumerazione dei processi (inclusi PlatformNotSupportedException
                // e altri errori dipendenti dal runtime/OS) restituisce un elenco vuoto.
                return [];
            }
        });
}
