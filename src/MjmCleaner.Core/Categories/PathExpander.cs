namespace MjmCleaner.Core.Categories;

/// <summary>Traduce i percorsi delle regole in percorsi assoluti.</summary>
public sealed class PathExpander
{
    private readonly string _home;
    private readonly string _temp;

    public PathExpander(string? homeDirectory, string? tempDirectory)
    {
        _home = Normalize(homeDirectory, nameof(homeDirectory));
        _temp = Normalize(tempDirectory, nameof(tempDirectory));
    }

    public string Expand(string path)
    {
        string expanded = path switch
        {
            "~" => _home,
            "$TMPDIR" => _temp,
            _ when path.StartsWith("~/", StringComparison.Ordinal) => _home + path[1..],
            _ => path,
        };

        return expanded.Length > 1 ? expanded.TrimEnd('/') : expanded;
    }

    public static PathExpander ForCurrentUser()
        => new(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            Path.GetTempPath());

    // Validato DOPO TrimEnd('/'), non prima: lo stesso difetto misurato in DenyList,
    // qui su due argomenti. Un valore come "//" o "/" supera indisturbato un controllo
    // sul solo valore grezzo, ma TrimEnd('/') lo riduce a "": Expand("~") o
    // Expand("$TMPDIR") restituirebbero allora la stringa vuota invece di lanciare.
    private static string Normalize(string? directory, string paramName)
    {
        if (string.IsNullOrEmpty(directory) || directory[0] != '/')
        {
            throw new ArgumentException(
                "Il percorso deve essere assoluto.",
                paramName);
        }

        string normalized = directory.TrimEnd('/');

        if (normalized.Length == 0)
        {
            throw new ArgumentException(
                "Il percorso deve restare un percorso assoluto non degenere dopo la normalizzazione.",
                paramName);
        }

        return normalized;
    }
}
