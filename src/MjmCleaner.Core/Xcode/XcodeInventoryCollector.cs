namespace MjmCleaner.Core.Xcode;

/// <summary>Application-facing inventory boundary; CLI source handling stays in <see cref="IXcodeCli"/>.</summary>
public sealed class XcodeInventoryCollector(IXcodeCli cli, IXcodeFileScanner? fileScanner = null) : IXcodeInventoryCollector
{
    public async Task<XcodeSnapshot> CollectAsync(CancellationToken ct)
    {
        XcodeSnapshot cliSnapshot = await cli.ReadInventoryAsync(ct);
        if (fileScanner is null)
        {
            return cliSnapshot;
        }

        XcodeSnapshot fileSnapshot = await fileScanner.ScanAsync(ct);
        XcodeSnapshot combined = new(
            [.. cliSnapshot.Candidates, .. fileSnapshot.Candidates],
            [.. cliSnapshot.Warnings, .. fileSnapshot.Warnings])
        {
            FileInventory = fileSnapshot.FileInventory,
        };
        return await fileScanner.MeasureRuntimeBackingImagesAsync(combined, ct);
    }
}
