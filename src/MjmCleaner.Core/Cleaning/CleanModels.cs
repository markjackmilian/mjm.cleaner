using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Cleaning;

public sealed record CategorySelection(string CategoryId, IReadOnlyList<ScanItem> Items);

public sealed record CategoryCleanResult(string CategoryId, long BytesFreed, int ItemsDeleted);

public sealed record CleanProgress(string CurrentPath, int ItemsDone, int ItemsTotal, long BytesFreed);

public sealed record CleanReport(
    DateTimeOffset StartedAtUtc,
    TimeSpan Duration,
    long BytesFreed,
    int ItemsDeleted,
    int ItemsFailed,
    IReadOnlyList<CategoryCleanResult> Categories,
    IReadOnlyList<ScanError> Errors,
    IReadOnlyList<string> DeletedPaths);
