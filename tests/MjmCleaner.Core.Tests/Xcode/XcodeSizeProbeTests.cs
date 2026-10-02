using MjmCleaner.Core.Docker;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Xcode;
using System.IO.Abstractions;

namespace MjmCleaner.Core.Tests.Xcode;

public class XcodeSizeProbeTests
{
    [Fact]
    public async Task AccessDeniedSizeIsUnknown()
    {
        string root = Path.Combine(Path.GetTempPath(), "mjm-xcode-probe-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        string directory = Path.Combine(root, "cache");
        Directory.CreateDirectory(directory);
        try
        {
            XcodeSizeProbe probe = new(new FileSystem(), new ThrowingRunner(new UnauthorizedAccessException()), new FileSystemLinkInspector(new FileSystem()), root);
            Assert.Null(await probe.MeasureAsync(directory, CancellationToken.None));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task PartialDuMeasurementIsUnknown()
    {
        string root = Path.Combine(Path.GetTempPath(), "mjm-xcode-probe-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            XcodeSizeProbe probe = new(new FileSystem(), new ReturningRunner(new ProcessResult(1, "12\tcache", "permission denied", false)), new FileSystemLinkInspector(new FileSystem()), root);
            Assert.Null(await probe.MeasureAsync(root, CancellationToken.None));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Fact]
    public async Task FreeBytesComeFromTheVolumeContainingHome()
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        XcodeSizeProbe probe = new(new FileSystem(), new ReturningRunner(new ProcessResult(0, "1\tunused", string.Empty, false)), new FileSystemLinkInspector(new FileSystem()), home);

        long? free = await probe.GetFreeBytesAsync(CancellationToken.None);

        Assert.NotNull(free);
        Assert.True(free >= 0);
    }

    private sealed class ThrowingRunner(Exception exception) : IProcessRunner
    {
        public Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> args, TimeSpan timeout, CancellationToken ct, IReadOnlyDictionary<string, string>? environment = null)
            => Task.FromException<ProcessResult>(exception);
    }

    private sealed class ReturningRunner(ProcessResult result) : IProcessRunner
    {
        public Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> args, TimeSpan timeout, CancellationToken ct, IReadOnlyDictionary<string, string>? environment = null)
            => Task.FromResult(result);
    }
}
