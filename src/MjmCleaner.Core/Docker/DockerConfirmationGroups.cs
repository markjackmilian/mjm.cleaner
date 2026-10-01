namespace MjmCleaner.Core.Docker;

public enum DockerGroupMode
{
    /// <summary>Si conferma in blocco con un'unica casella: le voci sicure.</summary>
    Block,

    /// <summary>Si confermano le singole voci, o tutte insieme dal gruppo.</summary>
    Selectable,

    /// <summary>Solo da leggere: le voci KEEP non si possono selezionare.</summary>
    ReadOnly,
}

public sealed record DockerConfirmationGroup(
    string Id,
    string Title,
    string Description,
    DockerGroupMode Mode,
    IReadOnlyList<DockerCandidate> Items)
{
    public bool SelectedByDefault => Mode == DockerGroupMode.Block;
}

/// <summary>
/// Raggruppa i candidati per la schermata di conferma e ricava la selezione da consegnare
/// all'esecutore. Logica pura nel Core, come <c>ConfirmationRows</c> per il wizard: ciò che
/// decide cosa viene cancellato va coperto dai test, non solo esercitato a mano nell'interfaccia.
/// </summary>
public static class DockerConfirmationGroups
{
    public const string SafeId = "safe";
    public const string LocalBuildsId = "local-builds";
    public const string UnusedImagesId = "unused-images";
    public const string UnusedVolumesId = "unused-volumes";
    public const string KeepId = "keep";

    public static IReadOnlyList<DockerConfirmationGroup> Build(IReadOnlyList<DockerCandidate> candidates)
    {
        DockerConfirmationGroup[] groups =
        [
            new(SafeId, "Eliminabili in sicurezza",
                "Immagini dangling, immagini che Testcontainers e Aspire ricreano da soli, cache di build. Si confermano in blocco.",
                DockerGroupMode.Block,
                [.. candidates.Where(c => c.Verdict == DockerVerdict.Delete)]),

            new(LocalBuildsId, "Costruite in locale",
                "Non si possono riscaricare: dopo la cancellazione vanno ricostruite dal loro Dockerfile.",
                DockerGroupMode.Selectable,
                [.. candidates.Where(c => c.Verdict == DockerVerdict.Ask)]),

            new(UnusedImagesId, "Immagini non usate",
                "Nessun container le usa. Costo: riscaricarle al prossimo utilizzo.",
                DockerGroupMode.Selectable,
                [.. candidates.Where(c => c.Verdict == DockerVerdict.Propose && c.Kind == DockerResourceKind.Image)]),

            new(UnusedVolumesId, "Volumi non montati",
                "I volumi contengono dati: cancellarli li perde per sempre. Quelli con nome si confermano uno alla volta.",
                DockerGroupMode.Selectable,
                [.. candidates.Where(c => c.Verdict == DockerVerdict.Propose && c.Kind == DockerResourceKind.Volume)]),

            new(KeepId, "Da tenere",
                "In uso, citate nei progetti o ricollegate da Aspire al prossimo avvio.",
                DockerGroupMode.ReadOnly,
                [.. candidates.Where(c => c.Verdict == DockerVerdict.Keep)]),
        ];

        return [.. groups.Where(g => g.Items.Count > 0)];
    }

    /// <summary>
    /// Un volume con nome che nessuna regola sa ricondurre a un progetto è il caso più rischioso:
    /// non lo seleziona la casella del gruppo, solo la sua.
    /// </summary>
    public static bool RequiresIndividualConfirmation(DockerCandidate candidate)
        => candidate.Kind == DockerResourceKind.Volume && candidate.RuleId == "named-unused";

    /// <summary>
    /// Le voci da consegnare all'esecutore. I gruppi a blocco contano per intero o per niente; i
    /// gruppi in sola lettura mai; le voci KEEP sono escluse comunque, qualunque cosa dica
    /// l'interfaccia.
    /// </summary>
    public static IReadOnlyList<DockerCandidate> Selection(
        IReadOnlyList<DockerConfirmationGroup> groups,
        Func<DockerConfirmationGroup, bool> isGroupSelected,
        Func<DockerCandidate, bool> isItemSelected)
        => [.. groups
            .SelectMany(group => group.Mode switch
            {
                DockerGroupMode.Block => isGroupSelected(group) ? group.Items : [],
                DockerGroupMode.Selectable => group.Items.Where(isItemSelected),
                _ => [],
            })
            .Where(candidate => candidate.Verdict != DockerVerdict.Keep)];
}
