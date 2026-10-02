namespace MjmCleaner.Core.Xcode;

public interface IXcodeCleanupService
{
    Task<XcodeSnapshot> AnalyzeAsync(CancellationToken ct);
    Task<XcodeCleanResult> ExecuteAsync(XcodeConfirmedPlan plan, IProgress<MjmCleaner.Core.Cleaning.CleanProgress>? progress, CancellationToken ct);
}

/// <summary>Combines the current inventory with a fail-closed Xcode process-state check.</summary>
public sealed class XcodeCleanupService(
    IXcodeInventoryCollector collector,
    IXcodeRunningProbe runningProbe,
    IXcodeCleanExecutor executor) : IXcodeCleanupService
{
    public async Task<XcodeSnapshot> AnalyzeAsync(CancellationToken ct)
    {
        XcodeSnapshot snapshot = await collector.CollectAsync(ct);
        XcodeRunningState state = await runningProbe.GetStateAsync(ct);
        if (state == XcodeRunningState.Unknown)
        {
            XcodeCandidate[] blocked = snapshot.Candidates.Select(candidate => candidate.Kind is XcodeResourceKind.DerivedData or XcodeResourceKind.DeviceSupport
                ? candidate with { BlockReason = candidate.BlockReason ?? "Impossibile verificare se Xcode è in esecuzione; ripeti l'analisi." }
                : candidate).ToArray();
            return new XcodeSnapshot(blocked, snapshot.Warnings)
            {
                FileInventory = new XcodeFileInventory(snapshot.FileInventory),
            };
        }

        return XcodeClassifier.Classify(snapshot, state == XcodeRunningState.Running);
    }

    public Task<XcodeCleanResult> ExecuteAsync(XcodeConfirmedPlan plan, IProgress<MjmCleaner.Core.Cleaning.CleanProgress>? progress, CancellationToken ct)
        => executor.ExecuteAsync(plan, progress, ct);
}
