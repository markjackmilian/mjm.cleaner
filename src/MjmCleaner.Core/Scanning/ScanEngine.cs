using MjmCleaner.Core.Categories;

namespace MjmCleaner.Core.Scanning;

public interface IScanEngine
{
    Task<IReadOnlyList<CategoryScanResult>> ScanAsync(
        IReadOnlyList<CleanupCategory> categories,
        IProgress<ScanProgress>? progress,
        CancellationToken ct);
}

/// <summary>
/// Scansiona le categorie in parallelo: attraversare ~/Library/Caches significa
/// centinaia di migliaia di file e l'interfaccia deve restare reattiva.
/// </summary>
public sealed class ScanEngine(RuleScanner scanner) : IScanEngine
{
    public async Task<IReadOnlyList<CategoryScanResult>> ScanAsync(
        IReadOnlyList<CleanupCategory> categories,
        IProgress<ScanProgress>? progress,
        CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();

        CategoryScanResult[] results = await Task.WhenAll(
            categories.Select(category => Task.Run(() => ScanCategory(category, progress, ct), ct)));

        return results;
    }

    private CategoryScanResult ScanCategory(
        CleanupCategory category,
        IProgress<ScanProgress>? progress,
        CancellationToken ct)
    {
        List<ScanItem> items = [];
        List<ScanError> errors = [];
        List<GuardExclusion> exclusions = [];

        foreach (CleanupRule rule in category.Rules)
        {
            ct.ThrowIfCancellationRequested();

            RuleScanOutcome outcome = scanner.Scan(rule, ct);
            items.AddRange(outcome.Items);
            errors.AddRange(outcome.Errors);
            exclusions.AddRange(outcome.Exclusions);

            progress?.Report(new ScanProgress(
                category.Id,
                rule.Root,
                items.Count,
                items.Sum(i => i.SizeBytes)));
        }

        long total = items.Sum(i => i.SizeBytes);

        progress?.Report(new ScanProgress(category.Id, string.Empty, items.Count, total));

        return new CategoryScanResult(category.Id, items, total, errors, exclusions);
    }
}
