namespace MjmCleaner.Core.Safety;

/// <summary>
/// Un percorso è "canonico" quando è assoluto, non contiene il carattere NUL, e non richiede
/// alcuna risoluzione: nessun segmento "." o "..", nessun separatore ridondante.
/// </summary>
/// <remarks>
/// Condiviso da <see cref="DenyList"/> e <see cref="PathGuard"/>, che devono rifiutare i
/// percorsi non canonici con la stessa identica definizione: un percorso che l'una accetta e
/// l'altro respinge (o viceversa) apre un varco fra le due linee di difesa. Non è usato da
/// <c>PathExpander</c>, che riceve percorsi con "~" e "$TMPDIR" — non percorsi già assoluti da
/// validare — e quindi non è un chiamante di questo controllo.
/// </remarks>
internal static class CanonicalPath
{
    public static bool IsCanonical(string? path, out string normalized)
    {
        if (string.IsNullOrWhiteSpace(path) || path[0] != '/' || path.Contains('\0'))
        {
            normalized = string.Empty;
            return false;
        }

        if (path.Contains("//", StringComparison.Ordinal)
            || path.Contains("/./", StringComparison.Ordinal)
            || path.Contains("/../", StringComparison.Ordinal)
            || path.EndsWith("/.", StringComparison.Ordinal)
            || path.EndsWith("/..", StringComparison.Ordinal))
        {
            normalized = string.Empty;
            return false;
        }

        string trimmed = path.TrimEnd('/');
        normalized = trimmed.Length == 0 ? "/" : trimmed;
        return true;
    }
}
