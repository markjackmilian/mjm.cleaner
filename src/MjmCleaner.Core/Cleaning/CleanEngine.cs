using System.Diagnostics;
using System.IO.Abstractions;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Cleaning;

public interface ICleanEngine
{
    Task<CleanReport> CleanAsync(
        IReadOnlyList<CategorySelection> selections,
        IProgress<CleanProgress>? progress,
        CancellationToken ct);
}

/// <summary>
/// Eliminazione definitiva. Sequenziale: su un singolo volume il parallelismo non
/// accelera e renderebbe il resoconto meno prevedibile.
/// </summary>
public sealed class CleanEngine(IFileSystem fileSystem, IPathGuard guard, TimeProvider clock)
    : ICleanEngine
{
    public Task<CleanReport> CleanAsync(
        IReadOnlyList<CategorySelection> selections,
        IProgress<CleanProgress>? progress,
        CancellationToken ct)
        => Task.Run(() => Clean(selections, progress, ct), CancellationToken.None);

    private CleanReport Clean(
        IReadOnlyList<CategorySelection> selections,
        IProgress<CleanProgress>? progress,
        CancellationToken ct)
    {
        DateTimeOffset startedAt = clock.GetUtcNow();
        long stamp = Stopwatch.GetTimestamp();

        List<CategoryCleanResult> categories = [];
        List<ScanError> errors = [];
        List<string> deleted = [];
        long totalBytes = 0;
        int totalDeleted = 0;
        int totalFailed = 0;
        int done = 0;
        int total = selections.Sum(s => s.Items.Count);

        foreach (CategorySelection selection in selections)
        {
            long categoryBytes = 0;
            int categoryDeleted = 0;

            foreach (ScanItem item in selection.Items)
            {
                // L'annullamento restituisce un resoconto parziale: ciò che è già stato
                // eliminato deve comunque finire nello storico.
                if (ct.IsCancellationRequested)
                {
                    break;
                }

                done++;

                GuardVerdict verdict = guard.Validate(item.Path, item.DeclaredRoot);
                if (!verdict.IsAllowed)
                {
                    errors.Add(new ScanError(item.Path, ScanErrorKind.Other, verdict.Reason));
                    totalFailed++;
                    continue;
                }

                // Si elimina il percorso che il guard ha VALIDATO, non quello di partenza:
                // validare una stringa e cancellarne un'altra è il difetto che renderebbe
                // aggirabile ogni controllo a monte.
                string target = verdict.CanonicalPathValidated;

                try
                {
                    if (item.IsDirectory)
                    {
                        fileSystem.Directory.Delete(target, recursive: true);
                    }
                    else
                    {
                        if (!fileSystem.File.Exists(target))
                        {
                            throw new FileNotFoundException("elemento non più presente", target);
                        }

                        fileSystem.File.Delete(target);
                    }

                    categoryBytes += item.SizeBytes;
                    categoryDeleted++;
                    deleted.Add(target);
                }
                catch (Exception ex) when (RuleScanner.IsExpected(ex))
                {
                    errors.Add(RuleScanner.Describe(item.Path, ex));
                    totalFailed++;
                }

                progress?.Report(new CleanProgress(item.Path, done, total, totalBytes + categoryBytes));
            }

            categories.Add(new CategoryCleanResult(selection.CategoryId, categoryBytes, categoryDeleted));
            totalBytes += categoryBytes;
            totalDeleted += categoryDeleted;
        }

        return new CleanReport(
            startedAt,
            Stopwatch.GetElapsedTime(stamp),
            totalBytes,
            totalDeleted,
            totalFailed,
            categories,
            errors,
            deleted);
    }
}
