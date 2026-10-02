using System.Diagnostics;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Docker;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Xcode;

public interface IXcodeCleanExecutor
{
    Task<XcodeCleanResult> ExecuteAsync(XcodeConfirmedPlan plan, IProgress<CleanProgress>? progress, CancellationToken ct);
}

/// <summary>Executes only the confirmed Xcode resources, revalidating each one immediately before removal.</summary>
public sealed class XcodeCleanExecutor(
    IXcodeCli cli,
    IXcodeInventoryCollector collector,
    ICleanEngine cleanEngine,
    IXcodeSizeProbe measures,
    IXcodeRunningProbe runningProbe,
    TimeProvider clock) : IXcodeCleanExecutor
{
    private static readonly TimeSpan VerificationTimeout = TimeSpan.FromSeconds(15);

    public async Task<XcodeCleanResult> ExecuteAsync(XcodeConfirmedPlan plan, IProgress<CleanProgress>? progress, CancellationToken ct)
    {
        ArgumentNullException.ThrowIfNull(plan);
        DateTimeOffset started = clock.GetUtcNow();
        long stamp = Stopwatch.GetTimestamp();
        List<XcodeItemResult> results = [];
        List<string> warnings = [];
        long? freeBefore = await TryFreeBytesAsync(ct);
        List<XcodeCandidate> ordered = [.. plan.Candidates.Where(c => c.Kind == XcodeResourceKind.Device), .. plan.Candidates.Where(c => c.Kind == XcodeResourceKind.Runtime), .. plan.Candidates.Where(c => c.Kind is XcodeResourceKind.DerivedData or XcodeResourceKind.DeviceSupport)];
        HashSet<string> deletedDevices = new(StringComparer.OrdinalIgnoreCase);

        foreach (XcodeCandidate approved in ordered)
        {
            if (ct.IsCancellationRequested)
            {
                results.Add(Result(approved, XcodeItemOutcome.Skipped, "Operazione annullata prima della rimozione.", null));
                continue;
            }

            try
            {
                XcodeRunningState running = await runningProbe.GetStateAsync(ct);
                XcodeSnapshot fresh = await collector.CollectAsync(ct);
                warnings.AddRange(fresh.Warnings.Select(w => w.Message).Distinct(StringComparer.Ordinal));
                if (!IsInventoryReadable(fresh, approved.Kind))
                {
                    results.Add(Result(approved, XcodeItemOutcome.Skipped, "Inventario non disponibile per verificare la risorsa.", null));
                    continue;
                }

                XcodeSnapshot classified = XcodeClassifier.Classify(fresh, running == XcodeRunningState.Running);
                if (running == XcodeRunningState.Unknown && IsFile(approved.Kind))
                {
                    results.Add(Result(approved, XcodeItemOutcome.Skipped, "Impossibile verificare se Xcode è in esecuzione.", null));
                    continue;
                }

                XcodeCandidate? current = classified.Candidates.FirstOrDefault(c => SameKey(c.Key, approved.Key));
                string? changed = CompareIdentity(plan, fresh, approved, current, deletedDevices);
                if (changed is not null)
                {
                    results.Add(Result(approved, XcodeItemOutcome.Skipped, changed, null));
                    continue;
                }

                if (current!.BlockReason is not null)
                {
                    results.Add(Result(approved, XcodeItemOutcome.Skipped, current.BlockReason, null));
                    continue;
                }

                if (approved.Kind == XcodeResourceKind.Runtime)
                {
                    string[] dependentSelected = approved.DependentDeviceKeys.Where(key => plan.Candidates.Any(c => c.Kind == XcodeResourceKind.Device && SameKey(c.Key, key))).ToArray();
                    if (dependentSelected.Any(key => !deletedDevices.Contains(key)))
                    {
                        results.Add(Result(approved, XcodeItemOutcome.Skipped, "Un dispositivo dipendente selezionato non è stato rimosso con verifica.", null));
                        continue;
                    }
                }

                if (IsFile(approved.Kind))
                {
                    await ExecuteFileAsync(plan, approved, progress, ct, results, warnings);
                    continue;
                }

                await ExecuteCliAsync(approved, progress, ct, results, warnings);
                if (approved.Kind == XcodeResourceKind.Device && results[^1].Outcome == XcodeItemOutcome.Deleted)
                {
                    deletedDevices.Add(XcodeClassifier.NormalizeSelectionKey(approved.Key));
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                results.Add(Result(approved, XcodeItemOutcome.Skipped, "Operazione annullata prima della rimozione.", null));
            }
            catch (Exception ex)
            {
                results.Add(Result(approved, XcodeItemOutcome.Failed, ex.Message, null));
            }

            progress?.Report(new CleanProgress(approved.Path ?? approved.Name, results.Count, ordered.Count, 0));
        }

        long? freeAfter = await TryFreeBytesAsync(CancellationToken.None);
        CleanReport report = MakeHistory(started, stamp, results);
        return new XcodeCleanResult(report, Array.AsReadOnly(results.ToArray()), freeBefore, freeAfter, Array.AsReadOnly(warnings.Distinct(StringComparer.Ordinal).ToArray()));
    }

    private async Task ExecuteFileAsync(XcodeConfirmedPlan plan, XcodeCandidate candidate, IProgress<CleanProgress>? progress, CancellationToken ct, List<XcodeItemResult> results, List<string> warnings)
    {
        if (!plan.FileInventory.TryGetValue(candidate.Key, out XcodeFileEntry? approvedEntry) || approvedEntry.Identity.LogicalSizeBytes is null)
        {
            results.Add(Result(candidate, XcodeItemOutcome.Skipped, "Identità della cartella incompleta.", null));
            return;
        }

        CleanReport report = await cleanEngine.CleanAsync(
            [new CategorySelection(Category(candidate.Kind), [approvedEntry.Item])], progress, ct);
        if (report.ItemsDeleted == 1)
        {
            results.Add(Result(candidate, XcodeItemOutcome.Deleted, "Cartella rimossa e verificata dal motore di pulizia.", report.BytesFreed));
        }
        else if (report.Errors.Count > 0)
        {
            results.Add(Result(candidate, XcodeItemOutcome.Failed, report.Errors[0].Message, null));
        }
        else
        {
            results.Add(Result(candidate, XcodeItemOutcome.Skipped, "La cartella non è stata rimossa.", null));
        }

        if (report.ItemsFailed > 0)
        {
            warnings.AddRange(report.Errors.Select(e => e.Message));
        }
    }

    private async Task ExecuteCliAsync(XcodeCandidate candidate, IProgress<CleanProgress>? progress, CancellationToken ct, List<XcodeItemResult> results, List<string> warnings)
    {
        ProcessResult? command = null;
        Exception? commandError = null;
        try
        {
            command = candidate.Kind == XcodeResourceKind.Device
                ? await cli.DeleteDeviceAsync(candidate.CliId!, ct)
                : await cli.DeleteRuntimeAsync(candidate.CliId!, ct);
        }
        catch (Exception ex)
        {
            commandError = ex;
        }

        XcodeSnapshot? verified = await TryVerifyAfterCommandAsync(warnings);
        if (verified is not null)
        {
            warnings.AddRange(verified.Warnings.Select(w => w.Message).Distinct(StringComparer.Ordinal));
        }

        if (verified is null || !IsInventoryReadable(verified, candidate.Kind))
        {
            results.Add(Result(candidate, XcodeItemOutcome.Uncertain, "Il comando è terminato senza poter verificare l'inventario successivo.", null));
        }
        else if (!verified.Candidates.Any(c => SameKey(c.Key, candidate.Key)))
        {
            long? estimate = candidate.SizeBytes;
            results.Add(Result(candidate, XcodeItemOutcome.Deleted, estimate is null ? "Risorsa assente dopo il comando; dimensione stimata sconosciuta." : "Risorsa assente dopo il comando.", estimate));
        }
        else if (commandError is OperationCanceledException || command?.TimedOut == true)
        {
            results.Add(Result(candidate, XcodeItemOutcome.Uncertain, "Il comando è stato interrotto e la risorsa risulta ancora presente.", null));
        }
        else
        {
            string reason = commandError?.Message ?? (command!.ExitCode == 0 ? "Il comando è riuscito ma la risorsa è ancora presente." : command.StdErr.Trim());
            results.Add(Result(candidate, XcodeItemOutcome.Failed, string.IsNullOrWhiteSpace(reason) ? "Il comando di rimozione non è riuscito." : reason, null));
        }

        progress?.Report(new CleanProgress(candidate.Name, results.Count, results.Count, 0));
    }

    private async Task<XcodeSnapshot?> TryVerifyAfterCommandAsync(List<string> warnings)
    {
        using CancellationTokenSource bounded = new(VerificationTimeout);
        try
        {
            return await collector.CollectAsync(bounded.Token);
        }
        catch (Exception ex)
        {
            warnings.Add($"Verifica successiva non disponibile: {ex.Message}");
            return null;
        }
    }

    private async Task<long?> TryFreeBytesAsync(CancellationToken ct)
    {
        try { return await measures.GetFreeBytesAsync(ct); }
        catch { return null; }
    }

    private static bool IsInventoryReadable(XcodeSnapshot snapshot, XcodeResourceKind kind)
        => !snapshot.Warnings.Any(w => w.ResourceGroup == kind);

    private static string? CompareIdentity(XcodeConfirmedPlan plan, XcodeSnapshot fresh, XcodeCandidate approved, XcodeCandidate? current, IReadOnlySet<string> deletedDevices)
    {
        if (current is null) return "La risorsa approvata non è più presente nell'inventario.";
        if (current.Kind != approved.Kind) return "Il tipo della risorsa è cambiato dall'analisi.";

        if (IsFile(approved.Kind))
        {
            if (approved.Path is null || current.Path is null || !string.Equals(approved.Path, current.Path, StringComparison.Ordinal)
                || !plan.FileInventory.TryGetValue(approved.Key, out XcodeFileEntry? captured)
                || !fresh.FileInventory.TryGetValue(approved.Key, out XcodeFileEntry? observed)
                || !SameFileIdentity(captured, observed))
            {
                return "Il percorso o i metadati della cartella sono cambiati dall'analisi.";
            }
            return null;
        }

        if (!Guid.TryParse(approved.CliId, out Guid oldId) || !Guid.TryParse(current.CliId, out Guid newId) || oldId != newId
            || !string.Equals(approved.Build, current.Build, StringComparison.Ordinal)
            || (approved.Kind == XcodeResourceKind.Runtime && !string.Equals(approved.RuntimeIdentifier, current.RuntimeIdentifier, StringComparison.Ordinal)))
        {
            return "L'identità o la build della risorsa è cambiata dall'analisi.";
        }

        string[] expectedDependencies = approved.DependentDeviceKeys.Select(XcodeClassifier.NormalizeSelectionKey)
            .Where(key => !deletedDevices.Contains(key)).Order(StringComparer.Ordinal).ToArray();
        if (approved.Kind == XcodeResourceKind.Runtime && !expectedDependencies
                .SequenceEqual(current.DependentDeviceKeys.Select(XcodeClassifier.NormalizeSelectionKey).Order(StringComparer.Ordinal), StringComparer.Ordinal))
        {
            return "Le dipendenze del runtime sono cambiate dall'analisi.";
        }

        return null;
    }

    private static bool SameFileIdentity(XcodeFileEntry captured, XcodeFileEntry observed)
        => captured.Identity.LogicalSizeBytes is not null
            && observed.Identity.LogicalSizeBytes is not null
            && captured.Identity == observed.Identity
            && captured.Item.IsDirectory == observed.Item.IsDirectory
            && string.Equals(captured.Item.Path, observed.Item.Path, StringComparison.Ordinal)
            && string.Equals(captured.Item.DeclaredRoot, observed.Item.DeclaredRoot, StringComparison.Ordinal);

    private static bool SameKey(string left, string right)
        => string.Equals(XcodeClassifier.NormalizeSelectionKey(left), XcodeClassifier.NormalizeSelectionKey(right), StringComparison.Ordinal);

    private static bool IsFile(XcodeResourceKind kind) => kind is XcodeResourceKind.DerivedData or XcodeResourceKind.DeviceSupport;

    private static string Category(XcodeResourceKind kind) => kind switch
    {
        XcodeResourceKind.DerivedData => "xcode-derived-data",
        XcodeResourceKind.DeviceSupport => "xcode-device-support",
        XcodeResourceKind.Device => "xcode-simulator-devices",
        XcodeResourceKind.Runtime => "xcode-runtimes",
        _ => throw new ArgumentOutOfRangeException(nameof(kind)),
    };

    private static XcodeItemResult Result(XcodeCandidate candidate, XcodeItemOutcome outcome, string reason, long? bytes)
        => new(candidate, outcome, reason, bytes);

    private static CleanReport MakeHistory(DateTimeOffset started, long stamp, IReadOnlyList<XcodeItemResult> results)
    {
        XcodeItemResult[] deleted = [.. results.Where(r => r.Outcome == XcodeItemOutcome.Deleted)];
        long bytes = deleted.Sum(r => r.VerifiedEstimatedBytes ?? 0);
        CategoryCleanResult[] categories = deleted.GroupBy(r => Category(r.Candidate.Kind), StringComparer.Ordinal)
            .Select(group => new CategoryCleanResult(group.Key, group.Sum(r => r.VerifiedEstimatedBytes ?? 0), group.Count())).ToArray();
        ScanError[] errors = results.Where(r => r.Outcome != XcodeItemOutcome.Deleted)
            .Select(r => new ScanError(r.Candidate.Path ?? r.Candidate.Name, ScanErrorKind.Other, r.Reason)).ToArray();
        return new CleanReport(started, Stopwatch.GetElapsedTime(stamp), bytes, deleted.Length, errors.Length, categories, errors,
            deleted.Select(r => r.Candidate.Path ?? r.Candidate.Key).ToArray());
    }
}
