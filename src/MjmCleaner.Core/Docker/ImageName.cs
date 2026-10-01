namespace MjmCleaner.Core.Docker;

/// <summary>
/// Riferimento a un'immagine ridotto a repository normalizzato e tag. Docker mostra lo stesso
/// repository in forme diverse ("alpine", "docker.io/library/alpine"): confrontare le stringhe
/// grezze farebbe sembrare diverse due immagini identiche, e una regola come "versione
/// superata" o "citata nei progetti" non scatterebbe mai.
/// </summary>
public sealed record ImageName(string Repository, string? Tag)
{
    private const string DefaultRegistry = "docker.io";

    /// <summary>Ultimo segmento del repository: "testcontainers/ryuk" → "ryuk".</summary>
    public string ShortName => Repository[(Repository.LastIndexOf('/') + 1)..];

    public static ImageName Parse(string reference)
    {
        string value = reference.Trim();

        // Il digest identifica il contenuto, non il nome: per il confronto conta solo repository:tag.
        int at = value.IndexOf('@');
        if (at >= 0)
        {
            value = value[..at];
        }

        // Il tag è dopo l'ultimo ":" che segue l'ultimo "/": in "localhost:5000/app" i due
        // punti appartengono al registro, non al tag.
        string? tag = null;
        int colon = value.LastIndexOf(':');
        if (colon > value.LastIndexOf('/'))
        {
            tag = value[(colon + 1)..];
            value = value[..colon];
        }

        return new ImageName(NormalizeRepository(value), string.IsNullOrEmpty(tag) ? null : tag);
    }

    private static string NormalizeRepository(string repository)
    {
        string lower = repository.ToLowerInvariant();
        int slash = lower.IndexOf('/');

        if (slash < 0)
        {
            return $"{DefaultRegistry}/library/{lower}";
        }

        string first = lower[..slash];
        bool hasRegistry = first.Contains('.') || first.Contains(':') || first == "localhost";

        return hasRegistry ? lower : $"{DefaultRegistry}/{lower}";
    }
}
