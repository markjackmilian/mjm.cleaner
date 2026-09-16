using System.IO.Abstractions;
using System.IO.Enumeration;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Scanning;

/// <summary>Interpreta una singola regola. Non segue mai i collegamenti simbolici.</summary>
public sealed class RuleScanner(
    IFileSystem fileSystem,
    IPathGuard guard,
    ILinkInspector links,
    TimeProvider clock)
{
    public RuleScanOutcome Scan(CleanupRule rule, CancellationToken ct)
    {
        List<ScanItem> items = [];
        List<ScanError> errors = [];
        List<GuardExclusion> exclusions = [];

        // Root assente: categoria vuota, non errore.
        if (!fileSystem.Directory.Exists(rule.Root))
        {
            return new RuleScanOutcome(items, errors, exclusions);
        }

        // La root si valida una volta sola, e la validazione risale fino alla radice del
        // filesystem: se la root stessa o un suo antenato è un collegamento simbolico,
        // ogni elemento trovato sotto di essa punterebbe altrove. È il caso di chi sposta
        // ~/Library/Caches su un disco esterno con un collegamento.
        GuardVerdict rootVerdict = guard.ValidateRoot(rule.Root);
        if (!rootVerdict.IsAllowed)
        {
            exclusions.Add(new GuardExclusion(rule.Root, rootVerdict.Reason));
            return new RuleScanOutcome(items, errors, exclusions);
        }

        switch (rule.Mode)
        {
            case ScanMode.ClearContents:
                ScanContents(rule, items, errors, exclusions, ct);
                break;
            case ScanMode.MatchingFiles:
                ScanFiles(rule, rule.Root, depth: 0, items, errors, exclusions, ct);
                break;
            case ScanMode.MatchingDirs:
                throw new NotSupportedException("MatchingDirs viene implementato nel Task 9.");
            default:
                throw new ArgumentOutOfRangeException(nameof(rule));
        }

        return new RuleScanOutcome(items, errors, exclusions);
    }

    private void ScanContents(
        CleanupRule rule,
        List<ScanItem> items,
        List<ScanError> errors,
        List<GuardExclusion> exclusions,
        CancellationToken ct)
    {
        foreach (string entry in Enumerate(rule.Root, errors))
        {
            ct.ThrowIfCancellationRequested();

            if (!Accept(entry, rule, isDirectoryCandidate: true, errors))
            {
                continue;
            }

            GuardVerdict verdict = guard.Validate(entry, rule.Root);
            if (!verdict.IsAllowed)
            {
                exclusions.Add(new GuardExclusion(entry, verdict.Reason));
                continue;
            }

            bool isLink = links.IsSymbolicLink(entry);
            bool isDirectory = !isLink && fileSystem.Directory.Exists(entry);
            long size = isLink ? 0 : isDirectory ? DirectorySize(entry, errors, ct) : FileSize(entry, errors);

            items.Add(new ScanItem(entry, size, isDirectory, rule.Root));
        }
    }

    private void ScanFiles(
        CleanupRule rule,
        string directory,
        int depth,
        List<ScanItem> items,
        List<ScanError> errors,
        List<GuardExclusion> exclusions,
        CancellationToken ct)
    {
        if (depth > rule.MaxDepth)
        {
            return;
        }

        foreach (string entry in Enumerate(directory, errors))
        {
            ct.ThrowIfCancellationRequested();

            if (links.IsSymbolicLink(entry))
            {
                continue;
            }

            if (fileSystem.Directory.Exists(entry))
            {
                ScanFiles(rule, entry, depth + 1, items, errors, exclusions, ct);
                continue;
            }

            string name = fileSystem.Path.GetFileName(entry);
            if (!MatchesGlobs(name, rule) || !Accept(entry, rule, isDirectoryCandidate: false, errors))
            {
                continue;
            }

            long size = FileSize(entry, errors);
            if (rule.MinSizeBytes is { } minSize && size < minSize)
            {
                continue;
            }

            GuardVerdict verdict = guard.Validate(entry, rule.Root);
            if (!verdict.IsAllowed)
            {
                exclusions.Add(new GuardExclusion(entry, verdict.Reason));
                continue;
            }

            items.Add(new ScanItem(entry, size, false, rule.Root));
        }
    }

    /// <summary>Applica il filtro di età. Per le directory si usa il timestamp più recente fra accesso e scrittura.</summary>
    private bool Accept(string path, CleanupRule rule, bool isDirectoryCandidate, List<ScanError> errors)
    {
        if (rule.MinAge is not { } minAge)
        {
            return true;
        }

        try
        {
            IFileSystemInfo info = isDirectoryCandidate && fileSystem.Directory.Exists(path)
                ? fileSystem.DirectoryInfo.New(path)
                : fileSystem.FileInfo.New(path);

            DateTime stamp = info.LastAccessTimeUtc > info.LastWriteTimeUtc
                ? info.LastAccessTimeUtc
                : info.LastWriteTimeUtc;

            return clock.GetUtcNow().UtcDateTime - stamp >= minAge;
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            errors.Add(Describe(path, ex));
            return false;
        }
    }

    private static bool MatchesGlobs(string name, CleanupRule rule)
    {
        foreach (string excluded in rule.ExcludeGlobs)
        {
            if (FileSystemName.MatchesSimpleExpression(excluded, name, ignoreCase: true))
            {
                return false;
            }
        }

        foreach (string included in rule.IncludeGlobs)
        {
            if (FileSystemName.MatchesSimpleExpression(included, name, ignoreCase: true))
            {
                return true;
            }
        }

        return false;
    }

    private IEnumerable<string> Enumerate(string directory, List<ScanError> errors)
    {
        try
        {
            return fileSystem.Directory.EnumerateFileSystemEntries(directory);
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            errors.Add(Describe(directory, ex));
            return [];
        }
    }

    private long DirectorySize(string directory, List<ScanError> errors, CancellationToken ct)
    {
        long total = 0;

        foreach (string entry in Enumerate(directory, errors))
        {
            ct.ThrowIfCancellationRequested();

            if (links.IsSymbolicLink(entry))
            {
                continue;
            }

            total += fileSystem.Directory.Exists(entry)
                ? DirectorySize(entry, errors, ct)
                : FileSize(entry, errors);
        }

        return total;
    }

    private long FileSize(string path, List<ScanError> errors)
    {
        try
        {
            return fileSystem.FileInfo.New(path).Length;
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            errors.Add(Describe(path, ex));
            return 0;
        }
    }

    internal static bool IsExpected(Exception ex)
        => ex is UnauthorizedAccessException or IOException;

    internal static ScanError Describe(string path, Exception ex) => ex switch
    {
        UnauthorizedAccessException => new ScanError(path, ScanErrorKind.AccessDenied, ex.Message),
        FileNotFoundException or DirectoryNotFoundException => new ScanError(path, ScanErrorKind.NotFound, ex.Message),
        IOException io when io.Message.Contains("not empty", StringComparison.OrdinalIgnoreCase)
            => new ScanError(path, ScanErrorKind.NotEmpty, io.Message),
        IOException => new ScanError(path, ScanErrorKind.InUse, ex.Message),
        _ => new ScanError(path, ScanErrorKind.Other, ex.Message),
    };
}
