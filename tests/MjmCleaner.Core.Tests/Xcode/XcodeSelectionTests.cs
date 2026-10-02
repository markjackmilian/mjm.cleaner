using MjmCleaner.Core.Xcode;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Tests.Xcode;

public class XcodeSelectionTests
{
    private const string DeviceKey = "11111111-1111-4111-8111-111111111111";
    private const string RuntimeKey = "runtime:22222222-2222-4222-8222-222222222222";

    [Fact]
    public void UnknownKeyIsRejected()
    {
        XcodeSnapshot snapshot = CreateSnapshot(Device(), Runtime([DeviceKey]));
        Assert.Throws<ArgumentException>(() => XcodeSelection.Preview(snapshot, new HashSet<string> { "unknown" }));
    }

    [Fact]
    public void DuplicateNormalizedUuidSelectionsCollapse()
    {
        XcodeSnapshot snapshot = CreateSnapshot(Device());
        XcodeConfirmation preview = XcodeSelection.Preview(snapshot, new HashSet<string>(StringComparer.Ordinal)
        {
            DeviceKey,
            DeviceKey.ToUpperInvariant(),
        });
        Assert.Single(preview.SelectedCandidates);
    }

    [Fact]
    public void DirectSelectionOfBlockedRowIsRejected()
    {
        XcodeCandidate blocked = Device() with { State = "Booted" };
        XcodeSnapshot snapshot = new(new[] { blocked }, Array.Empty<XcodeInventoryWarning>());
        Assert.Throws<ArgumentException>(() => XcodeSelection.Preview(snapshot, new HashSet<string> { DeviceKey }));
    }

    [Fact]
    public void SelectedFileWithoutGuardedInventoryIsRejected()
    {
        XcodeCandidate file = new("derived-data:/one", XcodeResourceKind.DerivedData, "One", Path: "/one", SizeBytes: 3);
        XcodeSnapshot snapshot = CreateSnapshot(file);
        Assert.Throws<ArgumentException>(() => XcodeSelection.Preview(snapshot, new HashSet<string> { file.Key }));
    }

    [Fact]
    public void SelectedFileWithIncompleteGuardedInventoryIsRejected()
    {
        XcodeCandidate file = new("derived-data:/one", XcodeResourceKind.DerivedData, "One", Path: "/one", SizeBytes: 3);
        ScanItem item = new("/elsewhere", 3, true, "/");
        XcodeFileEntry entry = new(item, new XcodeFileIdentity("/one", true, default, default, 3));
        XcodeSnapshot snapshot = CreateSnapshot(file) with { FileInventory = new XcodeFileInventory([new KeyValuePair<string, XcodeFileEntry>(file.Key, entry)]) };
        Assert.Throws<ArgumentException>(() => XcodeSelection.Preview(snapshot, new HashSet<string> { file.Key }));
    }

    [Fact]
    public void RetainedDependenciesRequireAcknowledgement()
    {
        XcodeConfirmation preview = XcodeSelection.Preview(CreateSnapshot(Device(), Runtime([DeviceKey])), new HashSet<string> { RuntimeKey });
        Assert.Contains(preview.RetainedDependentDevices, candidate => candidate.Key == DeviceKey);
        Assert.Throws<InvalidOperationException>(() => XcodeSelection.Confirm(preview, acknowledgeDependencies: false));
        Assert.Single(XcodeSelection.Confirm(preview, acknowledgeDependencies: true).Candidates);
    }

    [Fact]
    public void ConfirmDoesNotSelectDependentDevices()
    {
        XcodeConfirmation preview = XcodeSelection.Preview(CreateSnapshot(Device(), Runtime([DeviceKey])), new HashSet<string> { RuntimeKey });
        XcodeConfirmedPlan plan = XcodeSelection.Confirm(preview, acknowledgeDependencies: true);
        Assert.DoesNotContain(plan.Candidates, candidate => candidate.Key == DeviceKey);
        Assert.Equal(RuntimeKey, Assert.Single(plan.Candidates).Key);
    }

    [Fact]
    public void UnknownSizesRemainVisible()
    {
        XcodeCandidate unknown = new("derived-data:/unknown", XcodeResourceKind.DerivedData, "Unknown", Path: "/unknown", SizeBytes: null);
        ScanItem item = new("/unknown", 3, true, "/");
        XcodeFileEntry entry = new(item, new XcodeFileIdentity("/unknown", true, DateTime.UnixEpoch, DateTime.UnixEpoch, null));
        XcodeSnapshot snapshot = CreateSnapshot(unknown) with { FileInventory = new XcodeFileInventory([new KeyValuePair<string, XcodeFileEntry>(unknown.Key, entry)]) };
        XcodeConfirmation preview = XcodeSelection.Preview(snapshot, new HashSet<string> { unknown.Key });
        Assert.Equal(1, preview.UnknownSizeCount);
        Assert.Equal(0, preview.EstimatedBytes);
        Assert.Null(preview.SelectedCandidates.Single().SizeBytes);
    }

    [Fact]
    public void ConfirmationCopiesCandidatesAndGuardedInventory()
    {
        XcodeCandidate file = new("derived-data:/one", XcodeResourceKind.DerivedData, "One", Path: "/one", SizeBytes: 3);
        ScanItem item = new("/one", 3, true, "/");
        XcodeFileEntry entry = new(item, new XcodeFileIdentity("/one", true, DateTime.UnixEpoch, DateTime.UnixEpoch, 3));
        XcodeSnapshot snapshot = CreateSnapshot(file) with { FileInventory = new XcodeFileInventory([new KeyValuePair<string, XcodeFileEntry>(file.Key, entry)]) };
        XcodeConfirmation preview = XcodeSelection.Preview(snapshot, new HashSet<string> { file.Key });
        XcodeConfirmedPlan plan = XcodeSelection.Confirm(preview, acknowledgeDependencies: true);
        Assert.Same(entry, plan.FileInventory[file.Key]);
        Assert.Throws<NotSupportedException>(() => ((IList<XcodeCandidate>)plan.Candidates).Add(file));
    }

    private static XcodeSnapshot CreateSnapshot(params XcodeCandidate[] candidates) => XcodeClassifier.Classify(new XcodeSnapshot(candidates, Array.Empty<XcodeInventoryWarning>()), false);
    private static XcodeCandidate Device() => new(DeviceKey, XcodeResourceKind.Device, "iPhone 16", CliId: DeviceKey, State: "Shutdown", SizeBytes: 10);
    private static XcodeCandidate Runtime(IReadOnlyList<string>? dependencies) => new(RuntimeKey, XcodeResourceKind.Runtime, "iOS 18", CliId: "22222222-2222-4222-8222-222222222222", SizeBytes: 20, Dependencies: dependencies);
}
