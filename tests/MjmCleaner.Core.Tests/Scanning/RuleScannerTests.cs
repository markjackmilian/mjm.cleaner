using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Tests.Safety;

namespace MjmCleaner.Core.Tests.Scanning;

public class RuleScannerTests
{
    private const string Home = "/Users/tester";
    private const string CacheRoot = "/Users/tester/Library/Caches";
    private static readonly DateTimeOffset Now = new(2026, 9, 15, 12, 0, 0, TimeSpan.Zero);
    private static readonly string[] All = ["*"];

    private static RuleScanner Create(MockFileSystem fs, params string[] symlinks)
    {
        FakeLinkInspector links = new(symlinks);
        return new RuleScanner(fs, new PathGuard(new DenyList(Home), links, Home), links, new TestTimeProvider(Now));
    }

    private static MockFileData File(long size, DateTime? written = null)
    {
        MockFileData data = new(new byte[size]);
        DateTime stamp = written ?? Now.UtcDateTime;
        data.LastWriteTime = stamp;
        data.LastAccessTime = stamp;
        return data;
    }

    [Fact]
    public void ReturnsNothingWhenRootDoesNotExist()
    {
        MockFileSystem fs = new();
        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule("/Users/tester/Library/Developer/Xcode/DerivedData", ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.Empty(outcome.Items);
        Assert.Empty(outcome.Errors);
    }

    [Fact]
    public void ClearContentsListsDirectChildrenNotTheRoot()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/app1/dati.bin", File(100));
        fs.AddFile($"{CacheRoot}/solo.tmp", File(50));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.Equal(2, outcome.Items.Count);
        Assert.DoesNotContain(outcome.Items, i => i.Path == CacheRoot);
        Assert.Contains(outcome.Items, i => i.Path == $"{CacheRoot}/app1" && i.IsDirectory && i.SizeBytes == 100);
        Assert.Contains(outcome.Items, i => i.Path == $"{CacheRoot}/solo.tmp" && !i.IsDirectory && i.SizeBytes == 50);
    }

    [Fact]
    public void DirectorySizeIsSummedRecursively()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/app/a/1.bin", File(100));
        fs.AddFile($"{CacheRoot}/app/b/2.bin", File(250));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.Equal(350, outcome.Items.Single().SizeBytes);
    }

    [Fact]
    public void ItemsCarryTheDeclaredRoot()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/x.tmp", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.Equal(CacheRoot, outcome.Items.Single().DeclaredRoot);
    }

    [Fact]
    public void GuardRejectionBecomesExclusionNotItem()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Documents/riservato.pdf", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(Home, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.Empty(outcome.Items);
        Assert.NotEmpty(outcome.Exclusions);
    }

    [Fact]
    public void SymlinkIsListedButItsTargetIsNotTraversed()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/collegamento/dentro.bin", File(9999));

        RuleScanOutcome outcome = Create(fs, $"{CacheRoot}/collegamento").Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        ScanItem item = outcome.Items.Single();
        Assert.Equal($"{CacheRoot}/collegamento", item.Path);
        Assert.Equal(0, item.SizeBytes);
    }

    [Fact]
    public void MatchingFilesHonoursMinAge()
    {
        MockFileSystem fs = new();
        string logs = $"{Home}/Library/Logs";
        fs.AddFile($"{logs}/vecchio.log", File(10, Now.UtcDateTime.AddDays(-60)));
        fs.AddFile($"{logs}/recente.log", File(10, Now.UtcDateTime.AddDays(-2)));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(logs, ScanMode.MatchingFiles, All, [], MinAge: TimeSpan.FromDays(30)),
            CancellationToken.None);

        Assert.Equal($"{logs}/vecchio.log", outcome.Items.Single().Path);
    }

    [Fact]
    public void MatchingFilesHonoursGlobsAndExclusions()
    {
        MockFileSystem fs = new();
        string logs = $"{Home}/Library/Logs";
        fs.AddFile($"{logs}/a.log", File(10));
        fs.AddFile($"{logs}/b.txt", File(10));
        fs.AddFile($"{logs}/importante.log", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(logs, ScanMode.MatchingFiles, ["*.log"], ["importante.*"]),
            CancellationToken.None);

        Assert.Equal($"{logs}/a.log", outcome.Items.Single().Path);
    }

    [Fact]
    public void MatchingFilesHonoursMinSize()
    {
        MockFileSystem fs = new();
        string downloads = $"{Home}/Downloads";
        fs.AddFile($"{downloads}/grande.dmg", File(2000));
        fs.AddFile($"{downloads}/piccolo.txt", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(downloads, ScanMode.MatchingFiles, All, [], MinSizeBytes: 1000),
            CancellationToken.None);

        Assert.Equal($"{downloads}/grande.dmg", outcome.Items.Single().Path);
    }

    [Fact]
    public void CancellationStopsTheScan()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/a.tmp", File(10));
        using CancellationTokenSource cts = new();
        cts.Cancel();

        Assert.Throws<OperationCanceledException>(() =>
            Create(fs).Scan(new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []), cts.Token));
    }
}
