using MjmCleaner.Core.Docker;
using MjmCleaner.Core.Xcode;

namespace MjmCleaner.Core.Tests.Xcode;

public sealed class XcodeCleanupServiceTests
{
    [Theory]
    [InlineData("/Applications/Xcode.app/Contents/MacOS/Xcode", XcodeRunningState.Running)]
    [InlineData("/Applications/Xcode-beta.app/Contents/MacOS/Xcode-beta", XcodeRunningState.Running)]
    [InlineData("/usr/bin/simctl", XcodeRunningState.NotRunning)]
    public async Task RunningProbeClassifiesProcessListing(string processPath, XcodeRunningState expected)
    {
        XcodeRunningProbe probe = new(new ProcessListingRunner(new ProcessResult(0, processPath, "", false)));

        Assert.Equal(expected, await probe.GetStateAsync(CancellationToken.None));
    }

    [Fact]
    public async Task RunningProbeReturnsUnknownWhenListingFails()
    {
        XcodeRunningProbe probe = new(new ProcessListingRunner(new ProcessResult(1, "", "denied", false)));

        Assert.Equal(XcodeRunningState.Unknown, await probe.GetStateAsync(CancellationToken.None));
    }

    [Fact]
    public async Task AnalyzeBlocksFilesWhenXcodeStateCannotBeVerified()
    {
        const string path = "/Users/test/Library/Developer/Xcode/DerivedData/App";
        const string key = "derived-data:" + path;
        XcodeSnapshot raw = new([new XcodeCandidate(key, XcodeResourceKind.DerivedData, "App", path)], []);
        XcodeCleanupService service = new(new FixedCollector(raw), new UnknownRunningProbe(), new RecordingExecutor());

        XcodeSnapshot analyzed = await service.AnalyzeAsync(CancellationToken.None);

        Assert.NotNull(Assert.Single(analyzed.Candidates).BlockReason);
    }

    private sealed class FixedCollector(XcodeSnapshot snapshot) : IXcodeInventoryCollector
    {
        public Task<XcodeSnapshot> CollectAsync(CancellationToken ct) => Task.FromResult(snapshot);
    }

    private sealed class UnknownRunningProbe : IXcodeRunningProbe
    {
        public Task<XcodeRunningState> GetStateAsync(CancellationToken ct) => Task.FromResult(XcodeRunningState.Unknown);
    }

    private sealed class RecordingExecutor : IXcodeCleanExecutor
    {
        public Task<XcodeCleanResult> ExecuteAsync(XcodeConfirmedPlan plan, IProgress<MjmCleaner.Core.Cleaning.CleanProgress>? progress, CancellationToken ct)
            => throw new NotSupportedException();
    }

    private sealed class ProcessListingRunner(ProcessResult result) : IProcessRunner
    {
        public Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> args, TimeSpan timeout, CancellationToken ct, IReadOnlyDictionary<string, string>? environment = null)
            => Task.FromResult(result);
    }
}
