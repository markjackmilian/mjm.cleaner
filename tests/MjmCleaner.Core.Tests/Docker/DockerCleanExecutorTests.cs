using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Docker;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Tests.Scanning;

namespace MjmCleaner.Core.Tests.Docker;

public class DockerCleanExecutorTests
{
    private const string DfBefore = """
        {"Type":"Images","Size":"5.84GB","Reclaimable":"1GB"}
        {"Type":"Local Volumes","Size":"558.5MB","Reclaimable":"159MB"}
        {"Type":"Build Cache","Size":"106.9MB","Reclaimable":"106.9MB"}
        """;

    private const string DfAfter = """
        {"Type":"Images","Size":"5.5GB","Reclaimable":"0B"}
        {"Type":"Local Volumes","Size":"470MB","Reclaimable":"0B"}
        {"Type":"Build Cache","Size":"0B","Reclaimable":"0B"}
        """;

    private static readonly string RyukId = DockerFixtures.RyukId;

    private static DockerCandidate Image(string id, string name, DockerVerdict verdict = DockerVerdict.Delete)
        => new(DockerResourceKind.Image, id, name, 1_000, verdict, "rule", "motivo", "costo");

    private static DockerCandidate Volume(string name, DockerVerdict verdict = DockerVerdict.Propose)
        => new(DockerResourceKind.Volume, name, name, 1_000, verdict, "rule", "motivo", "costo");

    private static readonly DockerCandidate BuildCache =
        new(DockerResourceKind.BuildCache, DockerClassifier.BuildCacheId, "Cache di build", 1_000, DockerVerdict.Delete, "build-cache", "m", "c");

    /// <summary>CLI che accetta ogni cancellazione e restituisce il df prima e dopo.</summary>
    private static FakeDockerCli SucceedingCli()
    {
        int dfCalls = 0;
        return new FakeDockerCli()
            .On("system df --format {{json .}}", () => FakeDockerCli.Ok(dfCalls++ == 0 ? DfBefore : DfAfter))
            .OnPrefix("rmi ", _ => FakeDockerCli.Ok("Deleted"))
            .OnPrefix("volume rm ", args => FakeDockerCli.Ok(args[^1]))
            .On("builder prune -f", "Total reclaimed space: 106.9MB");
    }

    private static Task<DockerCleanResult> Execute(FakeDockerCli cli, params DockerCandidate[] selected)
        => new DockerCleanExecutor(cli, new TestTimeProvider(DateTimeOffset.UnixEpoch))
            .ExecuteAsync(selected, null, CancellationToken.None);

    [Fact]
    public async Task ImagesAreRemovedByIdNeverByTag()
    {
        FakeDockerCli cli = SucceedingCli();

        await Execute(cli, Image(RyukId, "testcontainers/ryuk:0.14.0"));

        Assert.Contains($"rmi {RyukId}", cli.CommandLines);
        Assert.DoesNotContain(cli.CommandLines, line => line.Contains("ryuk:0.14.0", StringComparison.Ordinal));
    }

    [Fact]
    public async Task NoCommandIsEverForcedOrAGlobalPrune()
    {
        FakeDockerCli cli = SucceedingCli();

        await Execute(cli, Image(RyukId, "ryuk"), Volume("old-data"), BuildCache);

        Assert.All(cli.Calls.Where(c => c[0] is "rmi" or "volume"), call =>
        {
            Assert.DoesNotContain("-f", call);
            Assert.DoesNotContain("--force", call);
        });
        Assert.DoesNotContain(cli.CommandLines, line => line.StartsWith("system prune", StringComparison.Ordinal));
        Assert.DoesNotContain(cli.CommandLines, line => line.Contains("--volumes", StringComparison.Ordinal));
        Assert.DoesNotContain(cli.CommandLines, line => line.Contains("-a", StringComparison.Ordinal) && line.Contains("prune", StringComparison.Ordinal));
    }

    [Fact]
    public async Task VolumesAndBuildCacheUseTheirOwnCommands()
    {
        FakeDockerCli cli = SucceedingCli();

        DockerCleanResult result = await Execute(cli, Volume("orbit.apphost-751ef8e8e6-storage-data"), BuildCache);

        Assert.Contains("volume rm orbit.apphost-751ef8e8e6-storage-data", cli.CommandLines);
        Assert.Contains("builder prune -f", cli.CommandLines);
        Assert.Equal(2, result.Report.ItemsDeleted);
    }

    [Fact]
    public async Task KeepVerdictsAreRefusedWithoutRunningAnything()
    {
        FakeDockerCli cli = SucceedingCli();

        DockerCleanResult result = await Execute(cli,
            Image(DockerFixtures.Mssql2025Id, "mssql 2025", DockerVerdict.Keep),
            Volume("mssql2025-data", DockerVerdict.Keep));

        Assert.DoesNotContain(cli.Calls, c => c[0] is "rmi" or "volume");
        Assert.Equal(2, result.Report.ItemsFailed);
        Assert.All(result.Report.Errors, e => Assert.Contains("KEEP", e.Message));
    }

    [Theory]
    [InlineData("testcontainers/ryuk:0.14.0")]
    [InlineData("sha256:abc")]
    [InlineData("-f")]
    public async Task ImageIdentifiersThatAreNotFullIdsAreRefused(string id)
    {
        FakeDockerCli cli = SucceedingCli();

        DockerCleanResult result = await Execute(cli, Image(id, id));

        Assert.DoesNotContain(cli.Calls, c => c[0] == "rmi");
        Assert.Equal(1, result.Report.ItemsFailed);
    }

    [Theory]
    [InlineData("-f")]
    [InlineData("--all")]
    [InlineData("")]
    public async Task VolumeNamesThatLookLikeFlagsAreRefused(string name)
    {
        FakeDockerCli cli = SucceedingCli();

        DockerCleanResult result = await Execute(cli, Volume(name));

        Assert.DoesNotContain(cli.Calls, c => c[0] == "volume");
        Assert.Equal(1, result.Report.ItemsFailed);
    }

    [Fact]
    public async Task RefusedImageIsReportedWithDockersReason()
    {
        FakeDockerCli cli = SucceedingCli()
            .OnPrefix($"rmi {DockerFixtures.AlpineId}", _ => FakeDockerCli.Fail(
                "Error response from daemon: conflict: unable to delete d4d4d4d4d4d4 (must be forced) - image is referenced in multiple repositories"));

        DockerCleanResult result = await Execute(cli, Image(DockerFixtures.AlpineId, "alpine:3.20"), Image(RyukId, "ryuk"));

        ScanError error = Assert.Single(result.Report.Errors);
        Assert.Equal("alpine:3.20", error.Path);
        Assert.Contains("referenced in multiple repositories", error.Message);
        Assert.Equal(1, result.Report.ItemsDeleted);
    }

    [Fact]
    public async Task ImageWithDependentChildrenIsRetriedAfterTheOthers()
    {
        int baseAttempts = 0;
        bool childDeleted = false;
        FakeDockerCli cli = SucceedingCli()
            .On($"rmi {DockerFixtures.AzureLinuxId}", () => ++baseAttempts == 1 && !childDeleted
                ? FakeDockerCli.Fail("Error response from daemon: conflict: unable to delete 34a22db497ff (cannot be forced) - image has dependent child images")
                : FakeDockerCli.Ok("Deleted"))
            .On($"rmi {DockerFixtures.DcptunId}", () => { childDeleted = true; return FakeDockerCli.Ok("Deleted"); });

        DockerCleanResult result = await Execute(cli,
            Image(DockerFixtures.AzureLinuxId, "azurelinux/base/core:3.0"),
            Image(DockerFixtures.DcptunId, "dcptun_developer_ms:0.25.13"));

        Assert.Equal(2, baseAttempts);
        Assert.Equal(2, result.Report.ItemsDeleted);
        Assert.Empty(result.Report.Errors);
    }

    [Fact]
    public async Task DaemonLostMidwayStopsAndReportsWhatIsLeft()
    {
        FakeDockerCli cli = SucceedingCli()
            .On($"rmi {DockerFixtures.AlpineId}", () => throw new DockerUnavailableException(DockerUnavailableException.NotRunning));

        DockerCleanResult result = await Execute(cli,
            Image(RyukId, "ryuk"),
            Image(DockerFixtures.AlpineId, "alpine:3.20"),
            Volume("old-data"));

        Assert.True(result.DaemonLost);
        Assert.Equal(1, result.Report.ItemsDeleted);
        Assert.Equal(2, result.Report.ItemsFailed);
        Assert.DoesNotContain("volume rm old-data", cli.CommandLines);
        Assert.Null(result.After);
        Assert.All(result.Report.Errors, e => Assert.Contains("Docker", e.Message));
    }

    [Fact]
    public async Task DaemonLostDuringARetryStillAccountsForEveryItem()
    {
        // La base fallisce per le immagini figlie; al ritentativo il daemon è sparito.
        int attempts = 0;
        FakeDockerCli cli = SucceedingCli()
            .On($"rmi {DockerFixtures.AzureLinuxId}", () => ++attempts == 1
                ? FakeDockerCli.Fail("conflict: image has dependent child images")
                : throw new DockerUnavailableException(DockerUnavailableException.NotRunning));

        DockerCleanResult result = await Execute(cli,
            Image(DockerFixtures.AzureLinuxId, "azurelinux"),
            Image(DockerFixtures.DcptunId, "dcptun"),
            Volume("old-data"),
            BuildCache);

        Assert.Equal(1, result.Report.ItemsDeleted);
        Assert.Equal(["azurelinux", "old-data", "Cache di build"], result.Report.Errors.Select(e => e.Path));
    }

    [Fact]
    public async Task BytesFreedAreTheSystemDfDeltaPerType()
    {
        DockerCleanResult result = await Execute(SucceedingCli(), Image(RyukId, "ryuk"), Volume("old-data"), BuildCache);

        Assert.Equal(340_000_000, result.Report.Categories.Single(c => c.CategoryId == DockerCategories.Images).BytesFreed);
        Assert.Equal(88_500_000, result.Report.Categories.Single(c => c.CategoryId == DockerCategories.Volumes).BytesFreed);
        Assert.Equal(106_900_000, result.Report.Categories.Single(c => c.CategoryId == DockerCategories.BuildCache).BytesFreed);
        Assert.Equal(340_000_000 + 88_500_000 + 106_900_000, result.Report.BytesFreed);
    }

    [Fact]
    public async Task CategoriesWithoutDeletionsGetNoBytes()
    {
        // Solo un volume cancellato: se nel frattempo un'immagine sparisce per altri motivi, quel
        // delta non va attribuito a questa pulizia.
        DockerCleanResult result = await Execute(SucceedingCli(), Volume("old-data"));

        Assert.Equal([DockerCategories.Volumes], result.Report.Categories.Select(c => c.CategoryId));
        Assert.Equal(88_500_000, result.Report.BytesFreed);
    }

    [Fact]
    public async Task DeletedResourcesAreLoggedWithTheirIdentity()
    {
        DockerCleanResult result = await Execute(SucceedingCli(), Image(RyukId, "testcontainers/ryuk:0.14.0"), Volume("old-data"), BuildCache);

        Assert.Equal(
            [$"docker:image:{RyukId} (testcontainers/ryuk:0.14.0)", "docker:volume:old-data", "docker:build-cache"],
            result.Report.DeletedPaths);
    }

    [Fact]
    public async Task CancellationReturnsAPartialReport()
    {
        using CancellationTokenSource cts = new();
        FakeDockerCli cli = SucceedingCli()
            .On($"rmi {RyukId}", () => { cts.Cancel(); return FakeDockerCli.Ok("Deleted"); });

        DockerCleanResult result = await new DockerCleanExecutor(cli, new TestTimeProvider(DateTimeOffset.UnixEpoch))
            .ExecuteAsync([Image(RyukId, "ryuk"), Image(DockerFixtures.AlpineId, "alpine")], null, cts.Token);

        Assert.Equal(1, result.Report.ItemsDeleted);
        Assert.DoesNotContain($"rmi {DockerFixtures.AlpineId}", cli.CommandLines);
    }

    [Fact]
    public async Task ProgressIsReportedForEveryItem()
    {
        List<CleanProgress> reports = [];

        await new DockerCleanExecutor(SucceedingCli(), new TestTimeProvider(DateTimeOffset.UnixEpoch))
            .ExecuteAsync([Image(RyukId, "ryuk"), Volume("old-data")], new SynchronousProgress(reports), CancellationToken.None);

        Assert.Equal([1, 2], reports.Select(r => r.ItemsDone));
    }

    private sealed class SynchronousProgress(List<CleanProgress> sink) : IProgress<CleanProgress>
    {
        public void Report(CleanProgress value) => sink.Add(value);
    }
}
