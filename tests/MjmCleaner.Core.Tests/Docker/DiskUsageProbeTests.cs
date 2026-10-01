using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Tests.Docker;

public class DiskUsageProbeTests
{
    private const string RawPath = "/Users/tester/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw";

    private sealed class DuRunner(string stdout, int exitCode = 0) : IProcessRunner
    {
        public List<IReadOnlyList<string>> Calls { get; } = [];

        public Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> args, TimeSpan timeout, CancellationToken ct, IReadOnlyDictionary<string, string>? environment = null)
        {
            Calls.Add([fileName, .. args]);
            return Task.FromResult(new ProcessResult(exitCode, stdout, string.Empty, false));
        }
    }

    [Theory]
    [InlineData("8677192\t/Users/tester/Docker.raw\n", 8_677_192L * 1024)]
    [InlineData("0\t/x\n", 0L)]
    public void ParsesTheKilobytesPrintedByDu(string output, long expected)
        => Assert.Equal(expected, DiskUsageProbe.ParseDuKilobytes(output));

    [Fact]
    public void UnreadableDuOutputIsUnknown()
        => Assert.Null(DiskUsageProbe.ParseDuKilobytes("du: Docker.raw: Operation not permitted"));

    [Fact]
    public void DefaultPathIsTheDockerDesktopDiskOnMacOS()
        => Assert.Equal(RawPath, DiskUsageProbe.DefaultPath("/Users/tester"));

    [Fact]
    public async Task SparseFileReportsBothAllocatedAndApparentSize()
    {
        MockFileSystem fs = new();
        fs.AddFile(RawPath, new MockFileData(new byte[4096]));
        DuRunner du = new("8\t" + RawPath + "\n");

        DockerDiskUsage usage = await new DiskUsageProbe(du, fs, RawPath).MeasureAsync(CancellationToken.None);

        Assert.True(usage.Exists);
        Assert.Equal(8 * 1024, usage.AllocatedBytes);
        Assert.Equal(4096, usage.ApparentBytes);
        Assert.Equal(["du", "-k", RawPath], du.Calls.Single());
    }

    [Fact]
    public async Task MissingDiskImageIsReportedWithoutRunningDu()
    {
        DuRunner du = new(string.Empty);

        DockerDiskUsage usage = await new DiskUsageProbe(du, new MockFileSystem(), RawPath).MeasureAsync(CancellationToken.None);

        Assert.False(usage.Exists);
        Assert.Null(usage.AllocatedBytes);
        Assert.Empty(du.Calls);
    }

    [Fact]
    public async Task FailingDuLeavesOnlyTheApparentSize()
    {
        MockFileSystem fs = new();
        fs.AddFile(RawPath, new MockFileData(new byte[10]));

        DockerDiskUsage usage = await new DiskUsageProbe(new DuRunner(string.Empty, exitCode: 1), fs, RawPath).MeasureAsync(CancellationToken.None);

        Assert.Null(usage.AllocatedBytes);
        Assert.Equal(10, usage.ApparentBytes);
    }
}
