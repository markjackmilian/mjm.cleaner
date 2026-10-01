using System.Text.RegularExpressions;

namespace MjmCleaner.Core.Docker;

public sealed record VolumeRule(string Id, Func<DockerVolume, VolumeRuleContext, RuleMatch?> Evaluate);

/// <summary>
/// Nome di un volume creato da .NET Aspire: <c>&lt;app&gt;.apphost-&lt;hash&gt;-&lt;risorsa&gt;-data</c>.
/// L'hash deriva dal percorso dell'AppHost: spostare o rinominare la cartella del progetto
/// produce un hash nuovo, e i volumi con il vecchio restano orfani.
/// </summary>
public sealed partial record AspireVolumeName(string App, string Hash, string Resource)
{
    [GeneratedRegex(@"^(?<app>.+?)\.apphost-(?<hash>[0-9a-f]{6,64})-(?<resource>.+)-data$")]
    private static partial Regex Pattern();

    public static AspireVolumeName? TryParse(string volumeName)
    {
        Match match = Pattern().Match(volumeName);
        return match.Success
            ? new AspireVolumeName(match.Groups["app"].Value, match.Groups["hash"].Value, match.Groups["resource"].Value)
            : null;
    }
}

public sealed class VolumeRuleContext
{
    public const string ComposeProjectLabel = "com.docker.compose.project";

    public VolumeRuleContext(DockerSnapshot snapshot, ProjectReferences references)
    {
        MountedBy = snapshot.Containers
            .SelectMany(c => c.VolumeNames.Select(volume => (Volume: volume, Container: c)))
            .GroupBy(x => x.Volume, StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => (IReadOnlyList<DockerContainer>)[.. g.Select(x => x.Container)], StringComparer.Ordinal);

        ComposeProjects = snapshot.ExistingComposeProjects
            .Concat(references.ComposeProjects)
            .ToHashSet(StringComparer.Ordinal);

        // Un hash è "in uso" per un'app quando un suo volume è montato da un container, anche
        // fermo: Aspire lo ricollegherà al prossimo avvio insieme agli altri volumi con lo stesso hash.
        AspireHashesInUse = MountedBy.Keys
            .Select(AspireVolumeName.TryParse)
            .OfType<AspireVolumeName>()
            .GroupBy(name => name.App, StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => (IReadOnlySet<string>)g.Select(n => n.Hash).ToHashSet(StringComparer.Ordinal), StringComparer.Ordinal);
    }

    public IReadOnlyDictionary<string, IReadOnlyList<DockerContainer>> MountedBy { get; }
    public IReadOnlySet<string> ComposeProjects { get; }
    public IReadOnlyDictionary<string, IReadOnlySet<string>> AspireHashesInUse { get; }
}

/// <summary>
/// Regole sui volumi in ordine di priorità. Un volume contiene dati: nessuna regola produce
/// DELETE, e nel dubbio si tiene.
/// </summary>
public static partial class VolumeRules
{
    private const string DataLost = "dati persi";

    [GeneratedRegex("^[0-9a-f]{64}$")]
    private static partial Regex AnonymousName();

    public static IReadOnlyList<VolumeRule> Default { get; } =
    [
        new("mounted", (volume, ctx) => ctx.MountedBy.TryGetValue(volume.Name, out IReadOnlyList<DockerContainer>? users)
            ? new RuleMatch(DockerVerdict.Keep, "montato da " + ImageRules.DescribeContainers(users), string.Empty)
            : null),

        new("anonymous", (volume, _) => AnonymousName().IsMatch(volume.Name)
            ? new RuleMatch(DockerVerdict.Propose, "volume anonimo non montato", DataLost)
            : null),

        new("compose-project", (volume, ctx) =>
            volume.Labels.GetValueOrDefault(VolumeRuleContext.ComposeProjectLabel) is { } project && ctx.ComposeProjects.Contains(project)
                ? new RuleMatch(DockerVerdict.Keep, $"progetto compose «{project}» ancora presente", string.Empty)
                : null),

        new("aspire-current", (volume, ctx) =>
            AspireVolumeName.TryParse(volume.Name) is { } name
            && ctx.AspireHashesInUse.TryGetValue(name.App, out IReadOnlySet<string>? hashes)
            && hashes.Contains(name.Hash)
                ? new RuleMatch(DockerVerdict.Keep, $"AppHost «{name.App}» in uso con lo stesso hash: Aspire lo ricollega al prossimo avvio", string.Empty)
                : null),

        new("aspire-stale", (volume, ctx) =>
            AspireVolumeName.TryParse(volume.Name) is { } name
            && ctx.AspireHashesInUse.TryGetValue(name.App, out IReadOnlySet<string>? hashes)
                ? new RuleMatch(
                    DockerVerdict.Propose,
                    $"hash AppHost vecchio (in uso: {string.Join(", ", hashes.Order(StringComparer.Ordinal))})",
                    DataLost)
                : null),

        new("named-unused", (_, _) => new RuleMatch(
            DockerVerdict.Propose,
            "volume con nome non montato: va confermato esplicitamente",
            DataLost)),
    ];
}
