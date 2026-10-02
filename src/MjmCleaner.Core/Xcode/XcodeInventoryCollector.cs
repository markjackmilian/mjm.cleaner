namespace MjmCleaner.Core.Xcode;

/// <summary>Application-facing inventory boundary; CLI source handling stays in <see cref="IXcodeCli"/>.</summary>
public sealed class XcodeInventoryCollector(IXcodeCli cli) : IXcodeInventoryCollector
{
    public Task<XcodeSnapshot> CollectAsync(CancellationToken ct) => cli.ReadInventoryAsync(ct);
}
