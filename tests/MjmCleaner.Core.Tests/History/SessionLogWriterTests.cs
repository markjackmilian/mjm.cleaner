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
}
