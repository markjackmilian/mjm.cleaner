using MjmCleaner.Core.Xcode;

namespace MjmCleaner.Core.Tests.Xcode;

public class XcodeClassifierTests
{
    [Fact]
    public void AllRowsStartDeselected()
    {
        XcodeSnapshot classified = XcodeClassifier.Classify(Snapshot(
            File("derived-data:/dd"), Device("11111111-1111-4111-8111-111111111111"), Runtime("runtime:22222222-2222-4222-8222-222222222222")), xcodeRunning: false);

        XcodeConfirmation preview = XcodeSelection.Preview(classified, new HashSet<string>());
        Assert.Empty(preview.SelectedCandidates);
    }

    [Fact]
    public void BootedDeviceAndItsRuntimeAreBlocked()
    {
        XcodeCandidate device = Device("11111111-1111-4111-8111-111111111111", state: "Booted");
        XcodeCandidate runtime = Runtime("runtime:22222222-2222-4222-8222-222222222222", dependencies: [device.Key]);

        XcodeSnapshot classified = XcodeClassifier.Classify(Snapshot(device, runtime), xcodeRunning: false);

        Assert.False(Assert.Single(classified.Candidates, c => c.Kind == XcodeResourceKind.Device).CanSelect);
        Assert.False(Assert.Single(classified.Candidates, c => c.Kind == XcodeResourceKind.Runtime).CanSelect);
    }

    [Fact]
    public void UnavailableDeviceWithVerifiedUuidRemainsSelectable()
    {
        XcodeCandidate unavailable = Device("11111111-1111-4111-8111-111111111111", state: "Unavailable") with
        {
            BlockReason = "Stato del dispositivo non verificato: Unavailable; ripeti l'analisi.",
        };
        XcodeSnapshot classified = XcodeClassifier.Classify(Snapshot(unavailable), xcodeRunning: false);
        Assert.True(Assert.Single(classified.Candidates).CanSelect);
    }

    [Fact]
    public void UnavailableDevicePreservesUnrelatedSafetyBlock()
    {
        XcodeCandidate unavailable = Device("11111111-1111-4111-8111-111111111111", state: "Unavailable") with
        {
            BlockReason = "UUID duplicato con metadati in conflitto.",
        };
        XcodeSnapshot classified = XcodeClassifier.Classify(Snapshot(unavailable), xcodeRunning: false);
        Assert.Equal("UUID duplicato con metadati in conflitto.", Assert.Single(classified.Candidates).BlockReason);
    }

    [Fact]
    public void DeviceWithoutMatchingCliUuidIsBlocked()
    {
        XcodeCandidate device = Device("11111111-1111-4111-8111-111111111111") with { CliId = "33333333-3333-4333-8333-333333333333" };
        XcodeSnapshot classified = XcodeClassifier.Classify(Snapshot(device), xcodeRunning: false);
        Assert.False(Assert.Single(classified.Candidates).CanSelect);
    }

    [Fact]
    public void XcodeRunningBlocksFileCleanup()
    {
        XcodeSnapshot classified = XcodeClassifier.Classify(Snapshot(File("derived-data:/dd"), File("device-support:/ds", XcodeResourceKind.DeviceSupport)), xcodeRunning: true);
        Assert.All(classified.Candidates, candidate => Assert.False(candidate.CanSelect));
    }

    private static XcodeSnapshot Snapshot(params XcodeCandidate[] candidates) => new(candidates, Array.Empty<XcodeInventoryWarning>());
    private static XcodeCandidate File(string key, XcodeResourceKind kind = XcodeResourceKind.DerivedData) => new(key, kind, key, SizeBytes: 5);
    private static XcodeCandidate Device(string key, string state = "Shutdown") => new(key, XcodeResourceKind.Device, "iPhone", CliId: key, State: state, RuntimeIdentifier: "iOS 18", SizeBytes: 7);
    private static XcodeCandidate Runtime(string key, IReadOnlyList<string>? dependencies = null) => new(key, XcodeResourceKind.Runtime, "iOS 18", CliId: "22222222-2222-4222-8222-222222222222", SizeBytes: 9, Dependencies: dependencies);
}
