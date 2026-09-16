using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Tests.Safety;

namespace MjmCleaner.Core.Tests.Scanning;

public class ScanEngineTests
{
    private const string Home = "/Users/tester";
    private static readonly DateTimeOffset Now = new(2026, 9, 15, 12, 0, 0, TimeSpan.Zero);
    private static readonly string[] All = ["*"];

    private static ScanEngine Create(MockFileSystem fs)
    {
        FakeLinkInspector links = new();
        RuleScanner scanner = new(fs, new PathGuard(new DenyList(Home), links, Home), links, new TestTimeProvider(Now));
        return new ScanEngine(scanner);
    }

    private static CleanupCategory Category(string id, params CleanupRule[] rules)
        => new(id, id, string.Empty, RiskLevel.Low, true, null, rules);

    [Fact]
    public async Task AggregatesBytesPerCategory()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Library/Caches/a.tmp", new MockFileData(new byte[100]));
        fs.AddFile($"{Home}/Library/Caches/b.tmp", new MockFileData(new byte[50]));

        IReadOnlyList<CategoryScanResult> results = await Create(fs).ScanAsync(
            [Category("caches", new CleanupRule($"{Home}/Library/Caches", ScanMode.ClearContents, All, []))],
            progress: null,
            CancellationToken.None);

        CategoryScanResult result = results.Single();
        Assert.Equal("caches", result.CategoryId);
        Assert.Equal(150, result.TotalBytes);
        Assert.Equal(2, result.Items.Count);
    }

    [Fact]
    public async Task MergesItemsFromAllRulesOfACategory()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Library/Caches/a.tmp", new MockFileData(new byte[10]));
        fs.AddFile($"{Home}/.cache/b.tmp", new MockFileData(new byte[20]));

        IReadOnlyList<CategoryScanResult> results = await Create(fs).ScanAsync(
            [Category(
                "misto",
                new CleanupRule($"{Home}/Library/Caches", ScanMode.ClearContents, All, []),
                new CleanupRule($"{Home}/.cache", ScanMode.ClearContents, All, []))],
            progress: null,
            CancellationToken.None);

        Assert.Equal(30, results.Single().TotalBytes);
    }

    [Fact]
    public async Task ReturnsOneResultPerCategoryInInputOrder()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Library/Caches/a.tmp", new MockFileData(new byte[10]));
        fs.AddFile($"{Home}/.cache/b.tmp", new MockFileData(new byte[10]));

        IReadOnlyList<CategoryScanResult> results = await Create(fs).ScanAsync(
            [
                Category("uno", new CleanupRule($"{Home}/Library/Caches", ScanMode.ClearContents, All, [])),
                Category("due", new CleanupRule($"{Home}/.cache", ScanMode.ClearContents, All, [])),
            ],
            progress: null,
            CancellationToken.None);

        Assert.Equal(["uno", "due"], results.Select(r => r.CategoryId));
    }

    [Fact]
    public async Task ReportsProgressForEachCategory()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Library/Caches/a.tmp", new MockFileData(new byte[10]));
        List<ScanProgress> reported = [];

        await Create(fs).ScanAsync(
            [Category("caches", new CleanupRule($"{Home}/Library/Caches", ScanMode.ClearContents, All, []))],
            new Progress<ScanProgress>(p => { lock (reported) { reported.Add(p); } }),
            CancellationToken.None);

        await Task.Delay(50); // Progress<T> consegna sul contesto di sincronizzazione
        Assert.Contains(reported, p => p.CategoryId == "caches");
    }

    [Fact]
    public async Task CancellationPropagates()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Library/Caches/a.tmp", new MockFileData(new byte[10]));
        using CancellationTokenSource cts = new();
        await cts.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            Create(fs).ScanAsync(
                [Category("caches", new CleanupRule($"{Home}/Library/Caches", ScanMode.ClearContents, All, []))],
                progress: null,
                cts.Token));
    }

    [Fact]
    public async Task CategoryWithoutRulesYieldsEmptyResult()
    {
        MockFileSystem fs = new();

        IReadOnlyList<CategoryScanResult> results = await Create(fs).ScanAsync(
            [Category("vuota")],
            progress: null,
            CancellationToken.None);

        Assert.Equal(0, results.Single().TotalBytes);
        Assert.Empty(results.Single().Items);
    }
}
