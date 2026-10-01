namespace MjmCleaner.Core.Docker;

public enum DockerVerdict { Keep, Delete, Propose, Ask }

public enum DockerResourceKind { Image, Volume, BuildCache }

/// <summary>
/// Da dove viene un'immagine. Con il containerd image store <c>RepoDigests</c> è valorizzato
/// anche per le immagini costruite in locale: l'origine si legge da <c>.Identity</c>.
/// </summary>
public enum ImageOrigin { Unknown, Pulled, Built }

/// <summary>Un container, anche fermo: un container fermo tiene in uso immagine e volumi quanto uno attivo.</summary>
public sealed record DockerContainer(
    string Id,
    string Name,
    string ImageId,
    string State,
    int ExitCode,
    IReadOnlyList<string> VolumeNames,
    IReadOnlyDictionary<string, string> Labels);

public sealed record DockerImage(
    string Id,
    IReadOnlyList<string> RepoTags,
    IReadOnlyList<string> RepoDigests,
    long SizeBytes,
    long? UniqueSizeBytes,
    IReadOnlyDictionary<string, string> Labels,
    ImageOrigin Origin)
{
    /// <summary>Senza tag, o con il solo segnaposto "&lt;none&gt;:&lt;none&gt;".</summary>
    public bool IsDangling => RepoTags.All(tag => tag == "<none>:<none>");

    public IEnumerable<ImageName> Names => RepoTags
        .Where(tag => tag != "<none>:<none>")
        .Select(ImageName.Parse);

    public string DisplayName => RepoTags.FirstOrDefault(tag => tag != "<none>:<none>") ?? ShortId(Id);

    public static string ShortId(string id)
    {
        string hex = id.StartsWith("sha256:", StringComparison.Ordinal) ? id[7..] : id;
        return hex.Length > 12 ? hex[..12] : hex;
    }
}

public sealed record DockerVolume(
    string Name,
    IReadOnlyDictionary<string, string> Labels,
    long? SizeBytes);

/// <summary>Una riga di <c>docker system df</c>: "Images", "Containers", "Local Volumes", "Build Cache".</summary>
public sealed record DockerDfEntry(string Type, long SizeBytes, long ReclaimableBytes);

public sealed record DockerDfSummary(IReadOnlyList<DockerDfEntry> Entries)
{
    public const string ImagesType = "Images";
    public const string VolumesType = "Local Volumes";
    public const string BuildCacheType = "Build Cache";

    public static DockerDfSummary Empty { get; } = new([]);

    public long Images => SizeOf(ImagesType);
    public long Volumes => SizeOf(VolumesType);
    public long BuildCache => SizeOf(BuildCacheType);
    public long Total => Entries.Sum(e => e.SizeBytes);

    public long SizeOf(string type) => Entries.FirstOrDefault(e => e.Type == type)?.SizeBytes ?? 0;
}

/// <summary>
/// Tutto ciò che la classificazione deve sapere, raccolto una volta sola. Immutabile e privo di
/// dipendenze dalla CLI: le regole lo leggono senza poter lanciare comandi né toccare il disco.
/// </summary>
/// <param name="ExistingComposeProjects">
/// Progetti compose la cui cartella esiste ancora, verificato dal collector (la verifica su
/// disco è I/O, quindi non può stare nelle regole).
/// </param>
public sealed record DockerSnapshot(
    IReadOnlyList<DockerContainer> Containers,
    IReadOnlyList<DockerImage> Images,
    IReadOnlyList<DockerVolume> Volumes,
    DockerDfSummary Df,
    IReadOnlySet<string> ExistingComposeProjects);

/// <summary>Esito della classificazione di una singola risorsa: cosa fare, perché, e quanto costa ricrearla.</summary>
public sealed record DockerCandidate(
    DockerResourceKind Kind,
    string Id,
    string DisplayName,
    long? SizeBytes,
    DockerVerdict Verdict,
    string RuleId,
    string Reason,
    string Cost)
{
    /// <summary>
    /// Solo le voci sicure (DELETE) partono selezionate. PROPOSE e ASK richiedono un gesto
    /// esplicito dell'utente; KEEP non è mai selezionabile.
    /// </summary>
    public bool SelectedByDefault => Verdict == DockerVerdict.Delete;
}
