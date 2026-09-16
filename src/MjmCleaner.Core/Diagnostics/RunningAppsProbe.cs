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
    private const int MinimumNameLength = 4;

    public IReadOnlyList<string> AffectedApps(IEnumerable<string> paths)
    {
        string[] candidates = [.. processNames()
            .Where(name => name.Length >= MinimumNameLength)
            .Distinct(StringComparer.OrdinalIgnoreCase)];

        if (candidates.Length == 0)
        {
            return [];
        }

        HashSet<string> affected = new(StringComparer.OrdinalIgnoreCase);

        foreach (string path in paths)
        {
            string name = Path.GetFileName(path);

            foreach (string candidate in candidates)
            {
                if (name.Contains(candidate, StringComparison.OrdinalIgnoreCase))
                {
                    affected.Add(candidate);
                }
            }
        }

        return [.. affected.Order(StringComparer.OrdinalIgnoreCase)];
    }

    public static RunningAppsProbe ForCurrentMachine()
        => new(() =>
        {
            try
            {
                return [.. Process.GetProcesses().Select(p => p.ProcessName)];
            }
            catch (InvalidOperationException)
            {
                return [];
            }
        });
}
