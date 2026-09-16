using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.History;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Tests.History;

public sealed class HistoryStoreTests : IDisposable
{
    private readonly string _directory =
        Path.Combine(Path.GetTempPath(), $"mjm-cleaner-test-{Guid.NewGuid():N}");

    private string DatabaseFile => Path.Combine(_directory, "history.db");

    public void Dispose()
    {
        // Senza questo il pool di connessioni tiene aperto il file e la cancellazione fallisce.
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();

        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }

    private static CleanReport Report(long bytes, int deleted = 1, int failed = 0, params CategoryCleanResult[] categories)
        => new(
            new DateTimeOffset(2026, 9, 15, 10, 30, 0, TimeSpan.Zero),
            TimeSpan.FromSeconds(38),
            bytes,
            deleted,
            failed,
            categories.Length > 0 ? categories : [new CategoryCleanResult("caches", bytes, deleted)],
            [],
            []);

    [Fact]
    public async Task InitializeCreatesSchemaAndIsIdempotent()
    {
        HistoryStore store = new(DatabaseFile);

        await store.InitializeAsync(CancellationToken.None);
        await store.InitializeAsync(CancellationToken.None);

        Assert.True(File.Exists(DatabaseFile));
        Assert.Equal(0, await store.GetTotalBytesFreedAsync(CancellationToken.None));
    }

    [Fact]
    public async Task SaveThenReadBackSession()
    {
        HistoryStore store = new(DatabaseFile);
        await store.InitializeAsync(CancellationToken.None);

        long id = await store.SaveAsync(Report(1_500), CancellationToken.None);

        CleanSessionSummary session = (await store.GetSessionsAsync(10, CancellationToken.None)).Single();
        Assert.Equal(id, session.Id);
        Assert.Equal(1_500, session.BytesFreed);
        Assert.Equal(TimeSpan.FromSeconds(38), session.Duration);
        Assert.Equal(new DateTimeOffset(2026, 9, 15, 10, 30, 0, TimeSpan.Zero), session.StartedAtUtc);
        Assert.Equal("caches", session.Categories.Single().CategoryId);
    }

    [Fact]
    public async Task TotalIsTheSumOfAllSessions()
    {
        HistoryStore store = new(DatabaseFile);
        await store.InitializeAsync(CancellationToken.None);

        await store.SaveAsync(Report(1_000), CancellationToken.None);
        await store.SaveAsync(Report(2_500), CancellationToken.None);

        Assert.Equal(3_500, await store.GetTotalBytesFreedAsync(CancellationToken.None));
    }

    [Fact]
    public async Task SessionsAreReturnedNewestFirstAndLimited()
    {
        HistoryStore store = new(DatabaseFile);
        await store.InitializeAsync(CancellationToken.None);

        long first = await store.SaveAsync(Report(10), CancellationToken.None);
        long second = await store.SaveAsync(Report(20), CancellationToken.None);
        long third = await store.SaveAsync(Report(30), CancellationToken.None);

        IReadOnlyList<CleanSessionSummary> sessions = await store.GetSessionsAsync(2, CancellationToken.None);

        Assert.Equal([third, second], sessions.Select(s => s.Id));
        Assert.DoesNotContain(sessions, s => s.Id == first);
    }

    [Fact]
    public async Task CategoryBreakdownIsPersisted()
    {
        HistoryStore store = new(DatabaseFile);
        await store.InitializeAsync(CancellationToken.None);

        await store.SaveAsync(
            Report(300, 3, 0, new CategoryCleanResult("caches", 100, 1), new CategoryCleanResult("logs", 200, 2)),
            CancellationToken.None);

        CleanSessionSummary session = (await store.GetSessionsAsync(1, CancellationToken.None)).Single();

        Assert.Equal(2, session.Categories.Count);
        Assert.Equal(200, session.Categories.Single(c => c.CategoryId == "logs").BytesFreed);
    }

    [Fact]
    public async Task FailedItemsAreRecorded()
    {
        HistoryStore store = new(DatabaseFile);
        await store.InitializeAsync(CancellationToken.None);

        await store.SaveAsync(Report(10, deleted: 1, failed: 4), CancellationToken.None);

        Assert.Equal(4, (await store.GetSessionsAsync(1, CancellationToken.None)).Single().ItemsFailed);
    }
}
