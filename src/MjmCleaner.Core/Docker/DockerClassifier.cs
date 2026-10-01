namespace MjmCleaner.Core.Docker;

/// <summary>
/// Classificazione pura: stesso snapshot, stessi riferimenti, stesso risultato. Nessuna chiamata
/// a Docker né al disco — è ciò che permette di verificarla con le sole fixture JSON.
/// </summary>
public static class DockerClassifier
{
    public const string BuildCacheId = "build-cache";

    public static IReadOnlyList<DockerCandidate> Classify(DockerSnapshot snapshot, ProjectReferences references)
        => Classify(snapshot, references, ImageRules.Default, VolumeRules.Default);

    public static IReadOnlyList<DockerCandidate> Classify(
        DockerSnapshot snapshot,
        ProjectReferences references,
        IReadOnlyList<ImageRule> imageRules,
        IReadOnlyList<VolumeRule> volumeRules)
    {
        ImageRuleContext imageContext = new(snapshot, references);
        VolumeRuleContext volumeContext = new(snapshot, references);
        List<DockerCandidate> candidates = [];

        foreach (DockerImage image in snapshot.Images)
        {
            (string ruleId, RuleMatch match) = FirstMatch(imageRules, rule => (rule.Id, rule.Evaluate(image, imageContext)));
            candidates.Add(new DockerCandidate(
                DockerResourceKind.Image,
                image.Id,
                image.DisplayName,
                image.SizeBytes,
                match.Verdict,
                ruleId,
                WithPossibleReference(match, image, references),
                match.Cost));
        }

        foreach (DockerVolume volume in snapshot.Volumes)
        {
            (string ruleId, RuleMatch match) = FirstMatch(volumeRules, rule => (rule.Id, rule.Evaluate(volume, volumeContext)));
            candidates.Add(new DockerCandidate(
                DockerResourceKind.Volume,
                volume.Name,
                volume.Name,
                volume.SizeBytes,
                match.Verdict,
                ruleId,
                match.Reason,
                match.Cost));
        }

        if (snapshot.Df.BuildCache > 0)
        {
            candidates.Add(new DockerCandidate(
                DockerResourceKind.BuildCache,
                BuildCacheId,
                "Cache di build",
                snapshot.Df.BuildCache,
                DockerVerdict.Delete,
                BuildCacheId,
                "cache di BuildKit",
                "solo tempo alla build successiva"));
        }

        return candidates;
    }

    private static (string RuleId, RuleMatch Match) FirstMatch<TRule>(
        IReadOnlyList<TRule> rules,
        Func<TRule, (string Id, RuleMatch? Match)> evaluate)
    {
        foreach (TRule rule in rules)
        {
            (string id, RuleMatch? match) = evaluate(rule);
            if (match is not null)
            {
                return (id, match);
            }
        }

        // Ogni elenco termina con una regola che si applica sempre: arrivare qui vuol dire che
        // un elenco personalizzato l'ha omessa, ed è un errore di programmazione, non di dati.
        throw new InvalidOperationException("Nessuna regola si applica: l'ultima regola dell'elenco deve applicarsi sempre.");
    }

    /// <summary>
    /// Un file che cita il repository senza tag ("AddKeycloak()") non basta a tenere un'immagine
    /// — terrebbe ogni versione del repository — ma l'utente deve saperlo prima di decidere.
    /// </summary>
    private static string WithPossibleReference(RuleMatch match, DockerImage image, ProjectReferences references)
    {
        if (match.Verdict is not (DockerVerdict.Propose or DockerVerdict.Ask))
        {
            return match.Reason;
        }

        ImageReference? possible = references.Images.FirstOrDefault(reference => reference.Tag is null
            && image.Names.Any(name => name.Repository == reference.Repository));

        return possible is null
            ? match.Reason
            : $"{match.Reason} · possibile riferimento in {possible.File}:{possible.Line}";
    }
}
