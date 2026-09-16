namespace MjmCleaner.Core.Safety;

public sealed record GuardVerdict(bool IsAllowed, string Reason)
{
    public static GuardVerdict Allow() => new(true, string.Empty);
    public static GuardVerdict Deny(string reason) => new(false, reason);
}

public interface IPathGuard
{
    GuardVerdict Validate(string candidatePath, string declaredRoot);
}

/// <summary>
/// Ultima linea di difesa: invocato immediatamente prima di ogni eliminazione,
/// non solo quando si definiscono le regole.
/// </summary>
public sealed class PathGuard(DenyList denyList, ILinkInspector links, string homeDirectory)
    : IPathGuard
{
    private const StringComparison Cmp = StringComparison.OrdinalIgnoreCase;
    private readonly string _home = homeDirectory.TrimEnd('/');

    public GuardVerdict Validate(string candidatePath, string declaredRoot)
    {
        // 1. Canonicalizzazione: risolve "." e ".." prima di qualsiasi confronto.
        string path = Path.GetFullPath(candidatePath).TrimEnd('/');
        string root = Path.GetFullPath(declaredRoot).TrimEnd('/');

        // 2. Contenimento nella root dichiarata dalla regola che ha prodotto l'elemento.
        if (!path.StartsWith(root + "/", Cmp) && !path.Equals(root, Cmp))
        {
            return GuardVerdict.Deny($"violazione del contenimento: fuori da {root}");
        }

        // 3. Deny-list.
        if (denyList.IsDenied(path, out string reason))
        {
            return GuardVerdict.Deny(reason);
        }

        // 4. Profondità minima: mai la home, mai un suo figlio diretto.
        if (IsHomeOrDirectChild(path))
        {
            return GuardVerdict.Deny("profondità insufficiente: figlio diretto della home");
        }

        // 5. Collegamenti simbolici: l'elemento stesso può essere un link (si elimina
        //    il link), ma un antenato che sia un link romperebbe il contenimento.
        for (string? ancestor = Path.GetDirectoryName(path);
             ancestor is not null && ancestor.Length > root.Length;
             ancestor = Path.GetDirectoryName(ancestor))
        {
            if (links.IsSymbolicLink(ancestor))
            {
                return GuardVerdict.Deny($"antenato è un collegamento simbolico: {ancestor}");
            }
        }

        return GuardVerdict.Allow();
    }

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
