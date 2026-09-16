namespace MjmCleaner.Core.Safety;

/// <summary>
/// Percorsi che non devono mai essere eliminati. Non configurabile dall'interfaccia:
/// è l'ultima linea di difesa, non una preferenza.
/// </summary>
public sealed class DenyList
{
    private const StringComparison Cmp = StringComparison.OrdinalIgnoreCase;

    private readonly string _home;
    private readonly string[] _denied;
    private readonly string[] _exceptions;

    public DenyList(string homeDirectory)
    {
        string home = homeDirectory.TrimEnd('/');
        _home = home;

        _denied =
        [
            "/System", "/usr", "/bin", "/sbin", "/etc", "/Applications", "/Library",
            $"{home}/Documents",
            $"{home}/Desktop",
            $"{home}/Pictures",
            $"{home}/Movies",
            $"{home}/Music",
            $"{home}/Library/Application Support",
            $"{home}/Library/Mobile Documents",
            $"{home}/Library/Keychains",
            $"{home}/.ssh",
            $"{home}/.gnupg",
            $"{home}/Library/Containers/com.docker.docker",
        ];

        _exceptions =
        [
            "/Library/Caches",
            "/Library/Logs",
        ];
    }

    /// <summary>Il percorso deve essere già canonicalizzato (vedi PathGuard).</summary>
    public bool IsDenied(string canonicalPath, out string reason)
    {
        string path = canonicalPath.TrimEnd('/');

        foreach (string allowed in _exceptions)
        {
            if (IsSameOrUnder(path, allowed))
            {
                reason = string.Empty;
                return false;
            }
        }

        // La home directory stessa è protetta, ma solo come blocco esatto: un confronto
        // ricorsivo (come per le altre voci) negherebbe l'intero albero sotto la home,
        // oscurando sia le eccezioni sia qualunque percorso pulibile non elencato.
        if (path.Equals(_home, Cmp))
        {
            reason = $"percorso protetto: {_home}";
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
