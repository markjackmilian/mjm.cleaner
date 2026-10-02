using MjmCleaner.Core.Docker;

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

public sealed record XcodeInventoryWarning(XcodeResourceKind ResourceGroup, string Message);

public sealed record XcodeSnapshot(
    IReadOnlyList<XcodeCandidate> Candidates,
    IReadOnlyList<XcodeInventoryWarning> Warnings)
{
    public static XcodeSnapshot Empty { get; } = new(Array.Empty<XcodeCandidate>(), Array.Empty<XcodeInventoryWarning>());
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
