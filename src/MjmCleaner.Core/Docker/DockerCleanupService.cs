using MjmCleaner.Core.Cleaning;

namespace MjmCleaner.Core.Docker;

/// <param name="ServerVersion">Versione del daemon che ha risposto.</param>
public sealed record DockerAnalysis(
    string ServerVersion,
    DockerSnapshot Snapshot,
    IReadOnlyList<DockerCandidate> Candidates,
    DockerDiskUsage Disk);

/// <summary>Il flusso completo per l'interfaccia: analisi in sola lettura, esecuzione, misura del disco.</summary>
public sealed class DockerCleanupService(
    DockerInventoryCollector collector,
    ProjectReferenceScanner scanner,
    DiskUsageProbe disk,
    DockerCleanExecutor executor)
{
    /// <summary>
    /// Raccolta da Docker e ricerca nei progetti procedono in parallelo: sono indipendenti, e la
    /// seconda attraversa il disco mentre la prima attende la CLI.
    /// </summary>
    public async Task<DockerAnalysis> AnalyzeAsync(IReadOnlyList<string> projectRoots, CancellationToken ct)
    {
        string version = await collector.CheckDaemonAsync(ct);

        Task<ProjectReferences> references = Task.Run(() => scanner.Scan(projectRoots, ct), ct);
        Task<DockerDiskUsage> usage = disk.MeasureAsync(ct);
        DockerSnapshot snapshot = await collector.CollectAsync(ct);

        return new DockerAnalysis(
            version,
            snapshot,
            DockerClassifier.Classify(snapshot, await references),
            await usage);
    }

    public Task<DockerCleanResult> ExecuteAsync(
        IReadOnlyList<DockerCandidate> selected,
        IProgress<CleanProgress>? progress,
        CancellationToken ct)
        => executor.ExecuteAsync(selected, progress, ct);

    public Task<DockerDiskUsage> MeasureDiskAsync(CancellationToken ct) => disk.MeasureAsync(ct);
}
