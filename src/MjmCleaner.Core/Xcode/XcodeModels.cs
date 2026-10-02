using MjmCleaner.Core.Docker;
using MjmCleaner.Core.Scanning;
using System.Collections.ObjectModel;

namespace MjmCleaner.Core.Xcode;

public enum XcodeResourceKind
{
    DerivedData,
    DeviceSupport,
    Device,
    Runtime,
}

public sealed record XcodeCandidate(
    string Key,
    XcodeResourceKind Kind,
    string Name,
    string? Path = null,
    string? CliId = null,
    string? RuntimeIdentifier = null,
    string? Build = null,
    string? State = null,
    long? SizeBytes = null,
    string? BlockReason = null,
    IReadOnlyList<string>? Dependencies = null)
{
    public bool CanSelect => BlockReason is null;

    public IReadOnlyList<string> DependentDeviceKeys => Dependencies ?? Array.Empty<string>();
}

public enum XcodeInventoryWarningKind { CompletenessFailure, Advisory }

public sealed record XcodeInventoryWarning(XcodeResourceKind ResourceGroup, string Message)
{
    /// <summary>Conservative for callers that have not yet classified their warning.</summary>
    public XcodeInventoryWarningKind Kind { get; init; } = XcodeInventoryWarningKind.CompletenessFailure;

    public static XcodeInventoryWarning CompletenessFailure(XcodeResourceKind group, string message)
        => new(group, message) { Kind = XcodeInventoryWarningKind.CompletenessFailure };

    public static XcodeInventoryWarning Advisory(XcodeResourceKind group, string message)
        => new(group, message) { Kind = XcodeInventoryWarningKind.Advisory };
}

public sealed record XcodeSnapshot(
    IReadOnlyList<XcodeCandidate> Candidates,
    IReadOnlyList<XcodeInventoryWarning> Warnings)
{
    public XcodeFileInventory FileInventory { get; init; } = XcodeFileInventory.Empty;

    public static XcodeSnapshot Empty { get; } = new(Array.Empty<XcodeCandidate>(), Array.Empty<XcodeInventoryWarning>());
}

/// <summary>Portable metadata captured with a guarded file candidate for later revalidation.</summary>
public sealed record XcodeFileIdentity(
    string CanonicalPath,
    bool IsDirectory,
    DateTime CreationTimeUtc,
    DateTime LastWriteTimeUtc,
    long? LogicalSizeBytes);

public sealed record XcodeFileEntry(ScanItem Item, XcodeFileIdentity Identity);

public enum XcodeItemOutcome { Deleted, Skipped, Failed, Uncertain }

public sealed record XcodeItemResult(
    XcodeCandidate Candidate,
    XcodeItemOutcome Outcome,
    string Reason,
    long? VerifiedEstimatedBytes);

public sealed record XcodeCleanResult(
    MjmCleaner.Core.Cleaning.CleanReport HistoryReport,
    IReadOnlyList<XcodeItemResult> Items,
    long? FreeBytesBefore,
    long? FreeBytesAfter,
    IReadOnlyList<string> Warnings);

/// <summary>Immutable candidate-key mapping; copied on construction so callers cannot mutate a scan.</summary>
public sealed class XcodeFileInventory : IReadOnlyDictionary<string, XcodeFileEntry>
{
    private readonly ReadOnlyDictionary<string, XcodeFileEntry> _items;

    public XcodeFileInventory(IEnumerable<KeyValuePair<string, XcodeFileEntry>> items)
    {
        _items = new ReadOnlyDictionary<string, XcodeFileEntry>(items.ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.Ordinal));
    }

    public static XcodeFileInventory Empty { get; } = new(Array.Empty<KeyValuePair<string, XcodeFileEntry>>());
    public XcodeFileEntry this[string key] => _items[key];
    public IEnumerable<string> Keys => _items.Keys;
    public IEnumerable<XcodeFileEntry> Values => _items.Values;
    public int Count => _items.Count;
    public bool ContainsKey(string key) => _items.ContainsKey(key);
    public bool TryGetValue(string key, out XcodeFileEntry value) => _items.TryGetValue(key, out value!);
    public IEnumerator<KeyValuePair<string, XcodeFileEntry>> GetEnumerator() => _items.GetEnumerator();
    System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator() => GetEnumerator();
}

public interface IXcodeCli
{
    Task<XcodeSnapshot> ReadInventoryAsync(CancellationToken ct);
    Task<ProcessResult> DeleteDeviceAsync(string uuid, CancellationToken ct);
    Task<ProcessResult> DeleteRuntimeAsync(string uuid, CancellationToken ct);
}

public interface IXcodeInventoryCollector
{
    Task<XcodeSnapshot> CollectAsync(CancellationToken ct);
}
