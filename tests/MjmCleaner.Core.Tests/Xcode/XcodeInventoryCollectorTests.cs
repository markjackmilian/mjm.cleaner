using MjmCleaner.Core.Xcode;

namespace MjmCleaner.Core.Tests.Xcode;

public class XcodeInventoryCollectorTests
{
    private sealed class FakeCli(XcodeSnapshot snapshot) : IXcodeCli
    {
        public Task<XcodeSnapshot> ReadInventoryAsync(CancellationToken ct) => Task.FromResult(snapshot);
        public Task<MjmCleaner.Core.Docker.ProcessResult> DeleteDeviceAsync(string uuid, CancellationToken ct) => throw new NotSupportedException();
        public Task<MjmCleaner.Core.Docker.ProcessResult> DeleteRuntimeAsync(string uuid, CancellationToken ct) => throw new NotSupportedException();
    }

    [Fact]
    public async Task EmptyInventoryIsSuccessful()
    {
        XcodeSnapshot snapshot = await new XcodeInventoryCollector(new FakeCli(XcodeSnapshot.Empty)).CollectAsync(CancellationToken.None);

        Assert.Empty(snapshot.Candidates);
        Assert.Empty(snapshot.Warnings);
    }
}
