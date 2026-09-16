namespace MjmCleaner.Core.Settings;

public sealed record CleanerSettings
{
    public IReadOnlyList<string> ProjectRoots { get; init; } = [];
    public IReadOnlyList<string> LargeFileRoots { get; init; } = [];
    public long LargeFileThresholdBytes { get; init; } = 500L * 1024 * 1024;
    public int DownloadsMinAgeDays { get; init; } = 90;
    public int LogsMinAgeDays { get; init; } = 30;
    public int NuGetMinAgeDays { get; init; } = 180;

    /// <summary>Selezione dell'ultimo utilizzo: riduce il costo dei quattro passi nella pulizia di routine.</summary>
    public IReadOnlyList<string> SelectedCategoryIds { get; init; } =
        ["system-caches", "dev-caches", "project-build-output", "logs"];
}
