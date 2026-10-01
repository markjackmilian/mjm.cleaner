using System.IO.Abstractions;

namespace MjmCleaner.Core.Docker;

/// <summary>
/// Raccoglie lo stato di Docker con soli comandi di lettura e in formato JSON. Ogni I/O che la
/// classificazione richiede (incluso controllare che la cartella di un progetto compose esista)
/// avviene qui, così che le regole restino funzioni pure dello snapshot.
/// </summary>
public sealed class DockerInventoryCollector(IDockerCli cli, IFileSystem fileSystem)
{
    private const string Json = "{{json .}}";
    private const string ComposeWorkingDirLabel = "com.docker.compose.project.working_dir";

    /// <summary>Verifica che il daemon risponda. Restituisce la versione del server.</summary>
    public async Task<string> CheckDaemonAsync(CancellationToken ct)
    {
        string output = await cli.RunCheckedAsync(["info", "--format", "{{json .ServerVersion}}"], ct);
        string version = output.Trim().Trim('"');

        // Senza daemon "docker info" può stampare comunque la parte client e uscire con 0:
        // una versione del server vuota è l'unico segnale affidabile.
        if (version.Length == 0 || version == "null")
        {
            throw new DockerUnavailableException(DockerUnavailableException.NotRunning);
        }

        return version;
    }

    public async Task<DockerSnapshot> CollectAsync(CancellationToken ct)
    {
        await CheckDaemonAsync(ct);

        // Container compresi quelli fermi (-a): un container fermo tiene in uso immagine e volumi.
        IReadOnlyList<string> containerIds = DockerJson.ParseLines(await cli.RunCheckedAsync(["ps", "-aq", "--no-trunc"], ct));
        IReadOnlyList<DockerContainer> containers = containerIds.Count == 0
            ? []
            : DockerJson.ParseContainers(await cli.RunCheckedAsync(["container", "inspect", .. containerIds], ct));

        IReadOnlyList<string> imageIds = DockerJson.ParseJsonLinesProperty(
            await cli.RunCheckedAsync(["images", "--no-trunc", "--format", Json], ct), "ID");
        IReadOnlyList<string> volumeNames = DockerJson.ParseJsonLinesProperty(
            await cli.RunCheckedAsync(["volume", "ls", "--format", Json], ct), "Name");

        DockerDfVerbose verbose = DockerJson.ParseDfVerbose(await cli.RunCheckedAsync(["system", "df", "-v", "--format", Json], ct));

        IReadOnlyList<DockerImage> images = imageIds.Count == 0
            ? []
            : DockerJson.ParseImages(await cli.RunCheckedAsync(["image", "inspect", .. imageIds], ct), verbose.ImageUniqueSizes);
        IReadOnlyList<DockerVolume> volumes = volumeNames.Count == 0
            ? []
            : DockerJson.ParseVolumes(await cli.RunCheckedAsync(["volume", "inspect", .. volumeNames], ct), verbose.VolumeSizes);

        DockerDfSummary df = await ReadDfAsync(ct);

        return new DockerSnapshot(containers, images, volumes, df, ExistingComposeProjects(containers));
    }

    public async Task<DockerDfSummary> ReadDfAsync(CancellationToken ct)
        => DockerJson.ParseDfSummary(await cli.RunCheckedAsync(["system", "df", "--format", Json], ct));

    /// <summary>
    /// I volumi compose portano solo il nome del progetto; la sua cartella si legge dalle etichette
    /// dei container dello stesso progetto. Le cartelle trovate nei progetti dell'utente si
    /// aggiungono in fase di classificazione (ProjectReferences.ComposeProjects).
    /// </summary>
    private HashSet<string> ExistingComposeProjects(IReadOnlyList<DockerContainer> containers)
    {
        HashSet<string> projects = new(StringComparer.Ordinal);

        foreach (DockerContainer container in containers)
        {
            if (container.Labels.GetValueOrDefault(VolumeRuleContext.ComposeProjectLabel) is { } project
                && container.Labels.GetValueOrDefault(ComposeWorkingDirLabel) is { } directory
                && fileSystem.Directory.Exists(directory))
            {
                projects.Add(project);
            }
        }

        return projects;
    }
}
