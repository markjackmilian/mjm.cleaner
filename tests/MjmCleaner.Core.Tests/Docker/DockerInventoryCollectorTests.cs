using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Tests.Docker;

public class DockerInventoryCollectorTests
{
    [Fact]
    public async Task CollectsTheWholeInventoryFromJsonOutput()
    {
        DockerSnapshot snapshot = await new DockerInventoryCollector(FakeDockerCli.WithRealCase(), new MockFileSystem())
            .CollectAsync(CancellationToken.None);

        Assert.Equal(2, snapshot.Containers.Count);
        Assert.Equal(10, snapshot.Images.Count);
        Assert.Equal(6, snapshot.Volumes.Count);
        Assert.Equal(76_740_000, snapshot.Images.Single(i => i.Id == DockerFixtures.DcptunId).UniqueSizeBytes);
        Assert.Equal(158_300_000, snapshot.Volumes.Single(v => v.Name == "orbit.apphost-48d90b1972-sql-data").SizeBytes);
        Assert.Equal(106_900_000, snapshot.Df.BuildCache);
    }

    [Fact]
    public async Task InspectsAllImagesInOneCallById()
    {
        FakeDockerCli cli = FakeDockerCli.WithRealCase();

        await new DockerInventoryCollector(cli, new MockFileSystem()).CollectAsync(CancellationToken.None);

        IReadOnlyList<string> inspect = Assert.Single(cli.Calls, c => c[0] == "image");
        Assert.Equal(12, inspect.Count);
        Assert.All(inspect.Skip(2), id => Assert.StartsWith("sha256:", id));
    }

    [Fact]
    public async Task OnlyReadOnlyCommandsAreUsed()
    {
        FakeDockerCli cli = FakeDockerCli.WithRealCase();

        await new DockerInventoryCollector(cli, new MockFileSystem()).CollectAsync(CancellationToken.None);

        string[] readOnly = ["info", "ps", "container inspect", "images", "image inspect", "volume ls", "volume inspect", "system df"];
        Assert.All(cli.CommandLines, line => Assert.Contains(readOnly, prefix => line.StartsWith(prefix, StringComparison.Ordinal)));
    }

    [Fact]
    public async Task EmptyListsAreNotInspected()
    {
        FakeDockerCli cli = new FakeDockerCli()
            .On("info --format {{json .ServerVersion}}", "\"29.8.0\"")
            .On("ps -aq --no-trunc", string.Empty)
            .On("images --no-trunc --format {{json .}}", string.Empty)
            .On("volume ls --format {{json .}}", string.Empty)
            .On("system df -v --format {{json .}}", """{"Images":[],"Containers":[],"Volumes":[],"BuildCache":[]}""")
            .On("system df --format {{json .}}", string.Empty);

        DockerSnapshot snapshot = await new DockerInventoryCollector(cli, new MockFileSystem()).CollectAsync(CancellationToken.None);

        Assert.Empty(snapshot.Images);
        Assert.DoesNotContain(cli.CommandLines, line => line.Contains("inspect", StringComparison.Ordinal));
    }

    [Fact]
    public async Task ComposeProjectExistsWhenItsWorkingDirectoryIsStillOnDisk()
    {
        const string containers = """
            [{"Id":"1","Name":"/shop-db-1","Image":"sha256:1","State":{"Status":"exited","ExitCode":0},"Mounts":[],
              "Config":{"Labels":{"com.docker.compose.project":"shop","com.docker.compose.project.working_dir":"/Users/tester/projects/shop"}}},
             {"Id":"2","Name":"/old-db-1","Image":"sha256:1","State":{"Status":"exited","ExitCode":0},"Mounts":[],
              "Config":{"Labels":{"com.docker.compose.project":"old","com.docker.compose.project.working_dir":"/Users/tester/projects/old"}}}]
            """;
        FakeDockerCli cli = new FakeDockerCli()
            .On("info --format {{json .ServerVersion}}", "\"29.8.0\"")
            .On("ps -aq --no-trunc", "1\n2\n")
            .On("container inspect 1 2", containers)
            .On("images --no-trunc --format {{json .}}", string.Empty)
            .On("volume ls --format {{json .}}", string.Empty)
            .On("system df -v --format {{json .}}", "{}")
            .On("system df --format {{json .}}", string.Empty);
        MockFileSystem fs = new();
        fs.AddDirectory("/Users/tester/projects/shop");

        DockerSnapshot snapshot = await new DockerInventoryCollector(cli, fs).CollectAsync(CancellationToken.None);

        Assert.Equal(["shop"], snapshot.ExistingComposeProjects);
    }

    [Fact]
    public async Task DaemonThatDoesNotAnswerStopsTheCollection()
    {
        FakeDockerCli cli = new FakeDockerCli()
            .On("info --format {{json .ServerVersion}}", () => throw new DockerUnavailableException(DockerUnavailableException.NotRunning));

        await Assert.ThrowsAsync<DockerUnavailableException>(
            () => new DockerInventoryCollector(cli, new MockFileSystem()).CollectAsync(CancellationToken.None));
        Assert.Single(cli.Calls);
    }

    [Fact]
    public async Task EmptyServerVersionMeansTheDaemonIsNotRunning()
    {
        // Senza daemon, "docker info" può comunque stampare la parte client e uscire con 0.
        FakeDockerCli cli = new FakeDockerCli().On("info --format {{json .ServerVersion}}", "\"\"");

        await Assert.ThrowsAsync<DockerUnavailableException>(
            () => new DockerInventoryCollector(cli, new MockFileSystem()).CollectAsync(CancellationToken.None));
    }
}
