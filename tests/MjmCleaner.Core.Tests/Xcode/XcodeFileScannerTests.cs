using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Docker;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Tests.Safety;
using MjmCleaner.Core.Xcode;

namespace MjmCleaner.Core.Tests.Xcode;

public class XcodeFileScannerTests
{
    private const string Home = "/Users/tester";
    private const string Xcode = Home + "/Library/Developer/Xcode";

    [Fact]
    public async Task DerivedDataIsGroupedByProjectFolder()
    {
        MockFileSystem fs = new();
        fs.AddFile(Xcode + "/DerivedData/App-abc/Build/Products/app", new MockFileData(new byte[17]));
        fs.AddFile(Xcode + "/DerivedData/Tool-xyz/Index.noindex/store", new MockFileData(new byte[29]));
        fs.AddFile(Xcode + "/DerivedData/loose-file", new MockFileData("ignore"));
        FakeSizeProbe sizes = new((Xcode + "/DerivedData/App-abc", 100), (Xcode + "/DerivedData/Tool-xyz", 200));
        XcodeFileScanner scanner = Create(fs, sizes);

        XcodeSnapshot snapshot = await scanner.ScanAsync(CancellationToken.None);

        XcodeCandidate[] candidates = snapshot.Candidates.Where(c => c.Kind == XcodeResourceKind.DerivedData).ToArray();
        Assert.Equal(new[] { "App-abc", "Tool-xyz" }, candidates.Select(c => c.Name).Order().ToArray());
        Assert.Equal(new long?[] { 100, 200 }, candidates.OrderBy(c => c.Name).Select(c => c.SizeBytes).ToArray());
        Assert.Equal(2, snapshot.FileInventory.Count);
        Assert.All(snapshot.FileInventory.Values, entry =>
        {
            Assert.True(entry.Item.IsDirectory);
            Assert.Equal(entry.Item.Path, entry.Identity.CanonicalPath);
            Assert.NotEqual(default, entry.Identity.CreationTimeUtc);
            Assert.NotEqual(default, entry.Identity.LastWriteTimeUtc);
        });
    }

    [Fact]
    public async Task ArchivesAndUserDataAreNeverCandidates()
    {
        MockFileSystem fs = new();
        fs.AddFile(Xcode + "/Archives/release.xcarchive/Products/app", new MockFileData(new byte[50]));
        fs.AddFile(Xcode + "/UserData/Provisioning Profiles/profile", new MockFileData(new byte[50]));

        XcodeSnapshot snapshot = await Create(fs, new FakeSizeProbe()).ScanAsync(CancellationToken.None);

        Assert.Empty(snapshot.Candidates);
        Assert.DoesNotContain(snapshot.FileInventory.Values, entry => entry.Item.Path.Contains("Archives", StringComparison.Ordinal));
        Assert.DoesNotContain(snapshot.FileInventory.Values, entry => entry.Item.Path.Contains("UserData", StringComparison.Ordinal));
    }

    [Fact]
    public async Task AbsentSupportFolderIsEmpty()
    {
        MockFileSystem fs = new();
        fs.AddFile(Xcode + "/DerivedData/App/Build/file", new MockFileData(new byte[1]));

        XcodeSnapshot snapshot = await Create(fs, new FakeSizeProbe()).ScanAsync(CancellationToken.None);

        Assert.DoesNotContain(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.DeviceSupport);
        Assert.DoesNotContain(snapshot.Candidates, candidate => candidate.Kind == XcodeResourceKind.DeviceSupport);
    }

    [Fact]
    public async Task LinkedRootIsRejected()
    {
        MockFileSystem fs = new();
        fs.AddFile(Xcode + "/DerivedData/App/Build/file", new MockFileData(new byte[1]));
        FakeLinkInspector links = new(Xcode + "/DerivedData");
        XcodeFileScanner scanner = Create(fs, new FakeSizeProbe(), links);

        XcodeSnapshot snapshot = await scanner.ScanAsync(CancellationToken.None);

        Assert.DoesNotContain(snapshot.Candidates, candidate => candidate.Kind == XcodeResourceKind.DerivedData);
        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.DerivedData);
    }

    [Fact]
    public async Task SharedBackingImageCountedOnce()
    {
        string backing = Home + "/Library/Developer/CoreSimulator/Images/shared.dmg";
        XcodeSnapshot original = new(
        [
            new XcodeCandidate("runtime:11111111-1111-4111-8111-111111111111", XcodeResourceKind.Runtime, "iOS 18", Path: backing),
            new XcodeCandidate("runtime:22222222-2222-4222-8222-222222222222", XcodeResourceKind.Runtime, "iOS 18 duplicate", Path: backing),
        ],
        []);
        MockFileSystem fs = new();
        fs.AddFile(backing, new MockFileData(new byte[1]));
        FakeSizeProbe sizes = new((backing, 4096));

        XcodeSnapshot measured = await Create(fs, sizes).MeasureRuntimeBackingImagesAsync(original, CancellationToken.None);

        Assert.Equal(4096, measured.Candidates.Single(c => c.Key.StartsWith("runtime:111", StringComparison.Ordinal)).SizeBytes);
        Assert.Null(measured.Candidates.Single(c => c.Key.StartsWith("runtime:222", StringComparison.Ordinal)).SizeBytes);
        Assert.Contains(measured.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Runtime && warning.Message.Contains("condivis", StringComparison.OrdinalIgnoreCase));
        Assert.Single(sizes.MeasuredPaths);
    }

    private static XcodeFileScanner Create(MockFileSystem fs, FakeSizeProbe sizes, FakeLinkInspector? links = null)
    {
        links ??= new FakeLinkInspector();
        PathGuard guard = new(new DenyList(Home), links, Home);
        RuleScanner rules = new(fs, guard, links, TimeProvider.System);
        return new XcodeFileScanner(fs, rules, guard, links, sizes, Home);
    }

    private sealed class FakeSizeProbe(params (string Path, long? Bytes)[] values) : IXcodeSizeProbe
    {
        private readonly Dictionary<string, long?> _values = values.ToDictionary(v => v.Path, v => v.Bytes);
        public List<string> MeasuredPaths { get; } = [];
        public Task<long?> MeasureAsync(string path, CancellationToken ct)
        {
            MeasuredPaths.Add(path);
            return Task.FromResult(_values.GetValueOrDefault(path));
        }
        public Task<long?> GetFreeBytesAsync(CancellationToken ct) => Task.FromResult<long?>(1234);
    }
}
