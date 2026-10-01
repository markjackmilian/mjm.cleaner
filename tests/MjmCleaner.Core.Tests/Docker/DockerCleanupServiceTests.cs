using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Tests.Docker;

public class DockerCleanupServiceTests
{
    private const string RawPath = "/Users/tester/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw";

    private sealed class NoProcess : IProcessRunner
    {
        public Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> args, TimeSpan timeout, CancellationToken ct, IReadOnlyDictionary<string, string>? environment = null)
            => Task.FromResult(new ProcessResult(0, "16\t" + RawPath, string.Empty, false));
    }

    private static DockerCleanupService Service(MockFileSystem fs, FakeDockerCli cli)
        => new(
            new DockerInventoryCollector(cli, fs),
            new ProjectReferenceScanner(fs),
            new DiskUsageProbe(new NoProcess(), fs, RawPath),
            new DockerCleanExecutor(cli, TimeProvider.System));

    [Fact]
    public async Task AnalysisClassifiesWithTheReferencesFoundInTheProjects()
    {
        MockFileSystem fs = new();
        fs.AddFile("/Users/tester/projects/orbit/Orbit.AppHost/Program.cs", new MockFileData("""
            var builder = DistributedApplication.CreateBuilder(args);
            builder.AddKeycloak("keycloak").WithImageTag("26.6");
            """));

        DockerAnalysis analysis = await Service(fs, FakeDockerCli.WithRealCase())
            .AnalyzeAsync(["/Users/tester/projects"], CancellationToken.None);

        DockerCandidate keycloak = analysis.Candidates.Single(c => c.DisplayName == "quay.io/keycloak/keycloak:26.6");
        Assert.Equal(DockerVerdict.Keep, keycloak.Verdict);
        Assert.Contains("Program.cs:2", keycloak.Reason);
    }

    [Fact]
    public async Task AnalysisMeasuresTheDiskImage()
    {
        MockFileSystem fs = new();
        fs.AddFile(RawPath, new MockFileData(new byte[100]));

        DockerAnalysis analysis = await Service(fs, FakeDockerCli.WithRealCase()).AnalyzeAsync([], CancellationToken.None);

        Assert.Equal(16 * 1024, analysis.Disk.AllocatedBytes);
        Assert.Equal(100, analysis.Disk.ApparentBytes);
        Assert.Equal(5_840_000_000, analysis.Snapshot.Df.Images);
    }
}
