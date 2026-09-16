namespace MjmCleaner.Core.Scanning;

/// <summary>Un elemento eliminabile. <paramref name="DeclaredRoot"/> serve al PathGuard per il contenimento.</summary>
public sealed record ScanItem(string Path, long SizeBytes, bool IsDirectory, string DeclaredRoot);

public enum ScanErrorKind { AccessDenied, InUse, NotFound, NotEmpty, Other }

public sealed record ScanError(string Path, ScanErrorKind Kind, string Message);

public sealed record GuardExclusion(string Path, string Reason);

public sealed record RuleScanOutcome(
    IReadOnlyList<ScanItem> Items,
    IReadOnlyList<ScanError> Errors,
    IReadOnlyList<GuardExclusion> Exclusions);

public sealed record CategoryScanResult(
    string CategoryId,
    IReadOnlyList<ScanItem> Items,
    long TotalBytes,
    IReadOnlyList<ScanError> Errors,
    IReadOnlyList<GuardExclusion> Exclusions);

public sealed record ScanProgress(string CategoryId, string CurrentPath, int ItemsFound, long BytesFound);
