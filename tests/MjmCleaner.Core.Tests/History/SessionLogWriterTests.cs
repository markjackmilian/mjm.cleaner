using System.IO.Abstractions.TestingHelpers;
using System.IO.Compression;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.History;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.Core.Tests.History;

public class SessionLogWriterTests
{
    private static readonly AppPaths Paths = new("/Users/tester");

    private static CleanReport Report(params string[] deletedPaths)
        => new(
            DateTimeOffset.UnixEpoch,
            TimeSpan.Zero,
            0,
            deletedPaths.Length,
            0,
            [],
            [],
            deletedPaths);

    [Fact]
    public async Task WritesOneLinePerDeletedPath()
    {
        MockFileSystem fs = new();
        SessionLogWriter writer = new(fs, Paths);

        await writer.WriteAsync(7, Report("/a/uno.tmp", "/a/due.tmp"), CancellationToken.None);

        string file = fs.Path.Combine(Paths.LogsDirectory, "session-000007.jsonl.gz");
        Assert.True(fs.File.Exists(file));

        using Stream raw = fs.File.OpenRead(file);
        using GZipStream unzipped = new(raw, CompressionMode.Decompress);
        using StreamReader reader = new(unzipped);
        string content = await reader.ReadToEndAsync();

        string[] lines = content.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        Assert.Equal(2, lines.Length);
        Assert.Contains("/a/uno.tmp", lines[0]);
        Assert.Contains("/a/due.tmp", lines[1]);
    }

    [Fact]
    public async Task KeepsOnlyTheMostRecentSessions()
    {
        MockFileSystem fs = new();
        SessionLogWriter writer = new(fs, Paths, retention: 3);

        for (long id = 1; id <= 5; id++)
        {
            await writer.WriteAsync(id, Report($"/a/{id}.tmp"), CancellationToken.None);
        }

        string[] remaining = [.. fs.Directory
            .EnumerateFiles(Paths.LogsDirectory)
            .Select(f => fs.Path.GetFileName(f)!)
            .Order()];

        Assert.Equal(
            ["session-000003.jsonl.gz", "session-000004.jsonl.gz", "session-000005.jsonl.gz"],
            remaining);
    }

    [Fact]
    public async Task CreatesTheLogsDirectoryWhenMissing()
    {
        MockFileSystem fs = new();
        SessionLogWriter writer = new(fs, Paths);

        await writer.WriteAsync(1, Report("/a/x.tmp"), CancellationToken.None);

        Assert.True(fs.Directory.Exists(Paths.LogsDirectory));
    }

    [Fact]
    public async Task OrdersRotationByNumericSessionIdNotByString()
    {
        // Oltre le sei cifre l'ordinamento lessicografico delle stringhe capovolge l'ordine:
        // "session-1000000..." precede "session-999999..." perché '1' < '9'. La rotazione deve
        // ordinare sul valore numerico estratto dal nome, non sulla stringa, altrimenti la
        // sessione appena scritta (1000000) verrebbe cancellata dalla propria rotazione al
        // posto della più vecchia (999997).
        MockFileSystem fs = new();
        SessionLogWriter writer = new(fs, Paths, retention: 3);

        foreach (long id in new long[] { 999_997, 999_998, 999_999, 1_000_000 })
        {
            await writer.WriteAsync(id, Report($"/a/{id}.tmp"), CancellationToken.None);
        }

        string[] remaining = [.. fs.Directory
            .EnumerateFiles(Paths.LogsDirectory)
            .Select(f => fs.Path.GetFileName(f)!)
            .Order()];

        Assert.Equal(
            ["session-1000000.jsonl.gz", "session-999998.jsonl.gz", "session-999999.jsonl.gz"],
            remaining);
    }

    [Fact]
    public async Task WritesAValidEmptyLogFileWhenNothingWasDeleted()
    {
        // Una pulizia che non ha eliminato nulla scrive comunque un file gzip valido, con
        // zero righe: la sessione è avvenuta e merita una traccia. Fissa questa scelta.
        MockFileSystem fs = new();
        SessionLogWriter writer = new(fs, Paths);

        await writer.WriteAsync(1, Report(), CancellationToken.None);

        string file = fs.Path.Combine(Paths.LogsDirectory, "session-000001.jsonl.gz");
        Assert.True(fs.File.Exists(file));
        Assert.Equal(15, fs.File.ReadAllBytes(file).Length);

        using Stream raw = fs.File.OpenRead(file);
        using GZipStream unzipped = new(raw, CompressionMode.Decompress);
        using StreamReader reader = new(unzipped);
        string content = await reader.ReadToEndAsync();

        Assert.Empty(content);
    }

    [Fact]
    public async Task PropagatesFailuresFromTheMainWriteInsteadOfSwallowingThem()
    {
        // Solo la rotazione intercetta IOException/UnauthorizedAccessException. Un fallimento
        // nella scrittura principale deve propagare al chiamante, che è ciò su cui il passo
        // finale dell'interfaccia farà affidamento per decidere come reagire.
        MockFileSystem fs = new();
        SessionLogWriter writer = new(fs, Paths);

        fs.Directory.CreateDirectory(Paths.LogsDirectory);
        string file = fs.Path.Combine(Paths.LogsDirectory, "session-000001.jsonl.gz");
        fs.AddFile(file, new MockFileData([]));
        fs.File.SetAttributes(file, FileAttributes.ReadOnly);

        await Assert.ThrowsAsync<UnauthorizedAccessException>(
            () => writer.WriteAsync(1, Report("/a/x.tmp"), CancellationToken.None));
    }
}
