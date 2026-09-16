namespace MjmCleaner.Core.Categories;

/// <summary>Traduce i percorsi delle regole in percorsi assoluti.</summary>
public sealed class PathExpander(string homeDirectory, string tempDirectory)
{
    private readonly string _home = homeDirectory.TrimEnd('/');
    private readonly string _temp = tempDirectory.TrimEnd('/');

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
}
