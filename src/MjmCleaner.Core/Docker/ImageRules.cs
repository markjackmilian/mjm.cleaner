namespace MjmCleaner.Core.Docker;

/// <summary>Esito di una regola che si applica: verdetto, motivo mostrato all'utente e costo per ricreare la risorsa.</summary>
public sealed record RuleMatch(DockerVerdict Verdict, string Reason, string Cost);

/// <summary>Una regola: restituisce null quando non si applica, e la valutazione passa alla successiva.</summary>
public sealed record ImageRule(string Id, Func<DockerImage, ImageRuleContext, RuleMatch?> Evaluate);

/// <summary>Fatti ricavati una sola volta dallo snapshot e condivisi da tutte le regole sulle immagini.</summary>
public sealed class ImageRuleContext
{
    public const string AspireBaseImageLabel = "com.microsoft.developer.usvc-dev.base-image-digest";
    public const string TestcontainersLabel = "org.testcontainers";

    public ImageRuleContext(DockerSnapshot snapshot, ProjectReferences references)
    {
        References = references;

        UsersByImageId = snapshot.Containers
            .GroupBy(c => c.ImageId, StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => (IReadOnlyList<DockerContainer>)[.. g], StringComparer.Ordinal);

        InUseTagsByRepository = snapshot.Images
            .Where(image => UsersByImageId.ContainsKey(image.Id))
            .SelectMany(image => image.Names)
            .Where(name => name.Tag is not null)
            .GroupBy(name => name.Repository, StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => (IReadOnlySet<string>)g.Select(n => n.Tag!).ToHashSet(StringComparer.Ordinal), StringComparer.Ordinal);

        // Le immagini base dichiarate dagli strumenti (il tunnel dcptun di Aspire indica la sua
        // in un'etichetta): lo strumento le riscarica da solo quando ricostruisce la derivata.
        Dictionary<string, string> toolBaseImages = new(StringComparer.Ordinal);
        foreach (DockerImage tool in snapshot.Images.Where(IsCreatedByTool))
        {
            if (tool.Labels.GetValueOrDefault(AspireBaseImageLabel) is { } digest)
            {
                toolBaseImages.TryAdd(digest, tool.DisplayName);
            }
        }

        ToolBaseImages = toolBaseImages;
    }

    public ProjectReferences References { get; }

    /// <summary>Container (anche fermi) per ID COMPLETO dell'immagine: mai per tag.</summary>
    public IReadOnlyDictionary<string, IReadOnlyList<DockerContainer>> UsersByImageId { get; }

    public IReadOnlyDictionary<string, IReadOnlySet<string>> InUseTagsByRepository { get; }

    /// <summary>Digest dell'immagine base → nome dell'immagine dello strumento che la dichiara.</summary>
    public IReadOnlyDictionary<string, string> ToolBaseImages { get; }

    public static bool IsCreatedByTool(DockerImage image)
        => image.Labels.GetValueOrDefault(TestcontainersLabel) == "true"
           || image.Names.Any(name => name.Repository.EndsWith("/testcontainers/ryuk", StringComparison.Ordinal)
                                      || name.ShortName.StartsWith("dcptun_", StringComparison.Ordinal));

    /// <summary>
    /// L'etichetta dello strumento contiene un digest: con il containerd store coincide con l'ID,
    /// con lo store classico è quello del manifest, che compare in <c>RepoDigests</c>.
    /// </summary>
    public string? ToolDeclaringAsBase(DockerImage image)
    {
        if (ToolBaseImages.TryGetValue(image.Id, out string? tool))
        {
            return tool;
        }

        foreach (string repoDigest in image.RepoDigests)
        {
            int at = repoDigest.IndexOf('@');
            if (at >= 0 && ToolBaseImages.TryGetValue(repoDigest[(at + 1)..], out tool))
            {
                return tool;
            }
        }

        return null;
    }
}

/// <summary>
/// Regole sulle immagini in ordine di priorità: vince la prima che si applica. Per aggiungere un
/// caso si aggiunge una riga, nel punto giusto dell'elenco.
/// </summary>
public static class ImageRules
{
    private const string Redownload = "riscaricare";

    public static IReadOnlyList<ImageRule> Default { get; } =
    [
        new("in-use", (image, ctx) => ctx.UsersByImageId.TryGetValue(image.Id, out IReadOnlyList<DockerContainer>? users)
            ? new RuleMatch(DockerVerdict.Keep, "usata da " + DescribeContainers(users), string.Empty)
            : null),

        new("dangling", (image, _) => image.IsDangling
            ? new RuleMatch(DockerVerdict.Delete, "immagine dangling, senza tag", "nessuno")
            : null),

        // Prima di "locally-built": il tunnel dcptun è costruito in locale da Aspire, ma è Aspire a
        // ricostruirlo al prossimo avvio — "non si può riscaricare" non è un costo per l'utente.
        new("tool-recreated", (image, ctx) =>
        {
            if (image.Labels.GetValueOrDefault(ImageRuleContext.TestcontainersLabel) == "true"
                || image.Names.Any(n => n.Repository.EndsWith("/testcontainers/ryuk", StringComparison.Ordinal)))
            {
                return new RuleMatch(DockerVerdict.Delete, "ricreata automaticamente da Testcontainers", "nessuno: la riscarica Testcontainers");
            }

            if (image.Names.Any(n => n.ShortName.StartsWith("dcptun_", StringComparison.Ordinal)))
            {
                return new RuleMatch(DockerVerdict.Delete, "tunnel di .NET Aspire, ricreato a ogni avvio", "nessuno: la ricostruisce Aspire");
            }

            return ctx.ToolDeclaringAsBase(image) is { } tool
                ? new RuleMatch(DockerVerdict.Delete, $"immagine base di {tool}", "nessuno: la riscarica lo strumento")
                : null;
        }),

        new("locally-built", (image, _) => IsLocallyBuilt(image)
            ? new RuleMatch(DockerVerdict.Ask, "costruita in locale: non si può riscaricare", "ricostruire dal Dockerfile")
            : null),

        new("referenced", (image, ctx) => ExactReference(image, ctx) is { } reference
            ? new RuleMatch(DockerVerdict.Keep, $"citata in {reference.File}:{reference.Line}", string.Empty)
            : null),

        new("superseded", (image, ctx) =>
        {
            foreach (ImageName name in image.Names)
            {
                if (ctx.InUseTagsByRepository.TryGetValue(name.Repository, out IReadOnlySet<string>? tags)
                    && tags.Any(tag => tag != name.Tag))
                {
                    return new RuleMatch(
                        DockerVerdict.Propose,
                        $"versione superata: in uso {string.Join(", ", tags.Order(StringComparer.Ordinal))}",
                        Redownload);
                }
            }

            return null;
        }),

        new("unused", (_, _) => new RuleMatch(DockerVerdict.Propose, "non usata da alcun container", Redownload)),
    ];

    /// <summary>
    /// Con <c>Identity</c> (Docker 29, containerd store) l'origine è esplicita; senza, ricade sul
    /// criterio dello store classico: nessun digest di registro.
    /// </summary>
    private static bool IsLocallyBuilt(DockerImage image) => image.Origin switch
    {
        ImageOrigin.Built => true,
        ImageOrigin.Pulled => false,
        _ => image.RepoDigests.Count == 0,
    };

    private static ImageReference? ExactReference(DockerImage image, ImageRuleContext ctx)
        => ctx.References.Images.FirstOrDefault(reference => reference.Tag is not null
            && image.Names.Any(name => name.Repository == reference.Repository && name.Tag == reference.Tag));

    internal static string DescribeContainers(IReadOnlyList<DockerContainer> containers)
        => string.Join(", ", containers.Select(c => $"{c.Name} ({(c.State == "running" ? "in esecuzione" : "fermo")})"));
}
