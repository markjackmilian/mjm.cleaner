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

    private sealed class FakeFileScanner(XcodeSnapshot files, long runtimeBytes) : IXcodeFileScanner
    {
        public bool ScanCalled { get; private set; }
        public bool MeasureCalled { get; private set; }
        public Task<XcodeSnapshot> ScanAsync(CancellationToken ct)
        {
            ScanCalled = true;
            return Task.FromResult(files);
        }

        public Task<XcodeSnapshot> MeasureRuntimeBackingImagesAsync(XcodeSnapshot snapshot, CancellationToken ct)
        {
            MeasureCalled = true;
            return Task.FromResult(snapshot with
            {
                Candidates = snapshot.Candidates.Select(candidate => candidate.Kind == XcodeResourceKind.Runtime
                    ? candidate with { SizeBytes = runtimeBytes }
                    : candidate).ToArray()
            });
        }
    }

    [Fact]
    public async Task EmptyInventoryIsSuccessful()
    {
        XcodeSnapshot snapshot = await new XcodeInventoryCollector(new FakeCli(XcodeSnapshot.Empty)).CollectAsync(CancellationToken.None);

        Assert.Empty(snapshot.Candidates);
        Assert.Empty(snapshot.Warnings);
    }

    [Fact]
    public async Task CollectorAddsFileRowsAndMeasuresRuntimeBackingSize()
    {
        XcodeSnapshot cliSnapshot = new(
        [new XcodeCandidate("runtime:11111111-1111-4111-8111-111111111111", XcodeResourceKind.Runtime, "iOS 18", Path: "/backing/AssetData")],
        []);
        XcodeSnapshot fileSnapshot = new(
        [new XcodeCandidate("derived-data:/Users/tester/Library/Developer/Xcode/DerivedData/App", XcodeResourceKind.DerivedData, "App")],
        []);
        FakeFileScanner scanner = new(fileSnapshot, 4096);

        XcodeSnapshot collected = await new XcodeInventoryCollector(new FakeCli(cliSnapshot), scanner).CollectAsync(CancellationToken.None);

        Assert.True(scanner.ScanCalled);
        Assert.True(scanner.MeasureCalled);
        Assert.Equal(4096, collected.Candidates.Single(candidate => candidate.Kind == XcodeResourceKind.Runtime).SizeBytes);
        Assert.Contains(collected.Candidates, candidate => candidate.Kind == XcodeResourceKind.DerivedData);
    }
}
