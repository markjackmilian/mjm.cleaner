using System.ComponentModel;
using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Tests.Docker;

public class DockerCliTests
{
    private sealed class FakeRunner(Func<string, IReadOnlyList<string>, ProcessResult> respond) : IProcessRunner
    {
        public List<(string File, IReadOnlyList<string> Args, IReadOnlyDictionary<string, string>? Env)> Calls { get; } = [];

        public Task<ProcessResult> RunAsync(
            string fileName,
            IReadOnlyList<string> args,
            TimeSpan timeout,
            CancellationToken ct,
            IReadOnlyDictionary<string, string>? environment = null)
        {
            Calls.Add((fileName, args, environment));
            return Task.FromResult(respond(fileName, args));
        }
    }

    [Theory]
    [InlineData("Cannot connect to the Docker daemon at unix:///Users/tester/.docker/run/docker.sock. Is the docker daemon running?")]
    [InlineData("error during connect: Get \"http://%2FUsers%2Ftester%2F.docker%2Frun%2Fdocker.sock/v1.47/info\": EOF")]
    [InlineData("failed to connect to the docker API at unix:///Users/tester/.docker/run/docker.sock; check if the path is correct and if the daemon is running: dial unix /Users/tester/.docker/run/docker.sock: connect: no such file or directory")]
    [InlineData("dial unix /var/run/docker.sock: connect: connection refused")]
    public void RecognizesAnUnreachableDaemon(string stderr)
        => Assert.True(DockerCliErrors.IsDaemonUnavailable(stderr));

    [Theory]
    [InlineData("Error response from daemon: conflict: unable to delete 2b5b58162112 (cannot be forced) - image is being used by running container e20bf2607c5b")]
    [InlineData("Error: No such image: testcontainers/ryuk:0.14.0")]
    [InlineData("")]
    public void OrdinaryErrorsAreNotADaemonOutage(string stderr)
        => Assert.False(DockerCliErrors.IsDaemonUnavailable(stderr));

    [Fact]
    public async Task ArgumentsArePassedVerbatimToTheLocatedBinary()
    {
        FakeRunner runner = new((_, _) => new ProcessResult(0, "ok", string.Empty, false));
        DockerCli cli = new(runner, "/Users/tester/.docker/bin/docker");

        ProcessResult result = await cli.RunAsync(["images", "--format", "{{json .}}"], CancellationToken.None);

        Assert.Equal("ok", result.StdOut);
        (string file, IReadOnlyList<string> args, IReadOnlyDictionary<string, string>? env) = Assert.Single(runner.Calls);
        Assert.Equal("/Users/tester/.docker/bin/docker", file);
        Assert.Equal(["images", "--format", "{{json .}}"], args);
        // Un'app aperta dal Finder non eredita il PATH della shell: i plugin e gli helper della
        // CLI (buildx, credential helper) vanno resi raggiungibili esplicitamente.
        Assert.StartsWith("/Users/tester/.docker/bin:", env!["PATH"]);
    }

    [Fact]
    public async Task UnreachableDaemonBecomesAReadableException()
    {
        FakeRunner runner = new((_, _) => new ProcessResult(1, string.Empty, "Cannot connect to the Docker daemon at unix:///x.sock. Is the docker daemon running?", false));
        DockerCli cli = new(runner, "/usr/local/bin/docker");

        DockerUnavailableException error = await Assert.ThrowsAsync<DockerUnavailableException>(
            () => cli.RunAsync(["info"], CancellationToken.None));

        Assert.Contains("Docker non è in esecuzione", error.Message);
    }

    [Fact]
    public async Task MissingBinaryBecomesAReadableException()
    {
        DockerCli cli = new(new FakeRunner((_, _) => throw new InvalidOperationException()), binaryPath: null);

        DockerUnavailableException error = await Assert.ThrowsAsync<DockerUnavailableException>(
            () => cli.RunAsync(["info"], CancellationToken.None));

        Assert.Contains("non è stato trovato", error.Message);
    }

    [Fact]
    public async Task BinaryThatCannotStartBecomesAReadableException()
    {
        DockerCli cli = new(new FakeRunner((_, _) => throw new Win32Exception(2, "No such file or directory")), "/usr/local/bin/docker");

        await Assert.ThrowsAsync<DockerUnavailableException>(() => cli.RunAsync(["info"], CancellationToken.None));
    }

    [Fact]
    public async Task CheckedRunFailsWithTheDockerErrorText()
    {
        FakeDockerCli cli = new FakeDockerCli().On("volume inspect x", () => FakeDockerCli.Fail("Error response from daemon: get x: no such volume"));

        DockerCommandException error = await Assert.ThrowsAsync<DockerCommandException>(
            () => cli.RunCheckedAsync(["volume", "inspect", "x"], CancellationToken.None));

        Assert.Contains("no such volume", error.Message);
    }

    [Fact]
    public async Task CheckedRunReportsATimeout()
    {
        FakeDockerCli cli = new FakeDockerCli().On("system df", () => new ProcessResult(-1, string.Empty, string.Empty, TimedOut: true));

        DockerCommandException error = await Assert.ThrowsAsync<DockerCommandException>(
            () => cli.RunCheckedAsync(["system", "df"], CancellationToken.None));

        Assert.Contains("tempo", error.Message);
    }

    [Fact]
    public void LocatorPrefersTheDockerDesktopUserBinary()
    {
        MockFileSystem fs = new();
        fs.AddFile("/usr/local/bin/docker", new MockFileData(string.Empty));
        fs.AddFile("/Users/tester/.docker/bin/docker", new MockFileData(string.Empty));

        Assert.Equal("/Users/tester/.docker/bin/docker", DockerBinaryLocator.Find(fs, "/Users/tester"));
    }

    [Fact]
    public void LocatorFallsBackToTheAppBundle()
    {
        MockFileSystem fs = new();
        fs.AddFile("/Applications/Docker.app/Contents/Resources/bin/docker", new MockFileData(string.Empty));

        Assert.Equal("/Applications/Docker.app/Contents/Resources/bin/docker", DockerBinaryLocator.Find(fs, "/Users/tester"));
    }

    [Fact]
    public void LocatorReturnsNullWhenDockerIsNotInstalled()
        => Assert.Null(DockerBinaryLocator.Find(new MockFileSystem(), "/Users/tester"));
}
