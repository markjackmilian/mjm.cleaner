using MjmCleaner.Core.Xcode;

namespace MjmCleaner.Core.Tests.Xcode;

public class XcodeJsonTests
{
    private static string Fixture(string name)
        => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Xcode", "Fixtures", name));

    [Fact]
    public void MalformedDevicesProducesWarningAndBlocksRuntimes()
    {
        XcodeSnapshot snapshot = XcodeJson.ParseInventory(Fixture("malformed-devices.json"), Fixture("runtime-list.json"), runtimeDeleteSupported: true);

        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Device && warning.Message.Length > 0);
        XcodeCandidate runtime = Assert.Single(snapshot.Candidates, candidate => candidate.Kind == XcodeResourceKind.Runtime);
        Assert.False(runtime.CanSelect);
        Assert.Contains("simulatori", runtime.BlockReason!, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void SameVersionDifferentBuildDoesNotGuess()
    {
        const string simctl = """
            {"devices":{},"runtimes":[
              {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","buildversion":"22A4000","platform":"iOS"}]}
            """;
        const string images = """
            {
              "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE":{"identifier":"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A4000","deletable":true},
              "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF":{"identifier":"BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A5000","deletable":true}
            }
            """;

        XcodeSnapshot snapshot = XcodeJson.ParseInventory(simctl, images, runtimeDeleteSupported: true);

        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Runtime);
        XcodeCandidate[] runtimes = snapshot.Candidates.Where(candidate => candidate.Kind == XcodeResourceKind.Runtime).ToArray();
        Assert.Equal(2, runtimes.Length);
        Assert.All(runtimes, runtime =>
        {
            Assert.False(runtime.CanSelect);
            Assert.Null(runtime.RuntimeIdentifier);
        });
    }

    [Fact]
    public void MissingRemovalUuidBlocksRuntime()
    {
        XcodeSnapshot snapshot = XcodeJson.ParseInventory(Fixture("simctl-list.json"), Fixture("runtime-list-missing-uuid.json"), runtimeDeleteSupported: true);

        XcodeCandidate runtime = Assert.Single(snapshot.Candidates, candidate => candidate.Kind == XcodeResourceKind.Runtime);
        Assert.False(runtime.CanSelect);
        Assert.Contains("UUID", runtime.BlockReason!, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void MalformedDeviceSourceStillKeepsRuntimeVisible()
    {
        XcodeSnapshot snapshot = XcodeJson.ParseInventory("{", Fixture("runtime-list.json"), runtimeDeleteSupported: true);

        Assert.Contains(snapshot.Candidates, candidate => candidate.Kind == XcodeResourceKind.Runtime);
        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Device);
    }

    [Fact]
    public void EmptyJsonInventoryIsSuccessful()
    {
        XcodeSnapshot snapshot = XcodeJson.ParseInventory("""{"runtimes":[],"devices":{}}""", "{}", runtimeDeleteSupported: true);

        Assert.Empty(snapshot.Candidates);
        Assert.Empty(snapshot.Warnings);
    }

    [Fact]
    public void MissingRuntimeMetadataKeepsValidDeviceEntry()
    {
        const string simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Shutdown"}]}}
            """;

        XcodeSnapshot snapshot = XcodeJson.ParseInventory(simctl, Fixture("runtime-list.json"), runtimeDeleteSupported: true);

        XcodeCandidate device = Assert.Single(snapshot.Candidates, candidate => candidate.Kind == XcodeResourceKind.Device);
        Assert.Equal("11111111-1111-4111-8111-111111111111", device.CliId);
        Assert.True(device.CanSelect);
        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Runtime);
        XcodeCandidate runtime = Assert.Single(snapshot.Candidates, candidate => candidate.Kind == XcodeResourceKind.Runtime);
        Assert.False(runtime.CanSelect);
    }

    [Fact]
    public void MalformedDeviceSiblingPreservesKnownDeviceButBlocksDeletion()
    {
        const string simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Shutdown"},
              {"udid":"invalid","name":"Broken device","state":"Shutdown"}]}}
            """;

        XcodeSnapshot snapshot = XcodeJson.ParseInventory(simctl, "{}", runtimeDeleteSupported: true);

        XcodeCandidate device = Assert.Single(snapshot.Candidates, candidate => candidate.Kind == XcodeResourceKind.Device);
        Assert.Equal("11111111-1111-4111-8111-111111111111", device.CliId);
        Assert.False(device.CanSelect);
        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Device);
    }

    [Fact]
    public void UnknownDeviceStateBlocksDeviceAndDependentRuntime()
    {
        const string simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"MysteryState"}]},
             "runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","buildversion":"22A3351","platform":"iOS"}]}
            """;

        XcodeSnapshot snapshot = XcodeJson.ParseInventory(simctl, Fixture("runtime-list.json"), runtimeDeleteSupported: true);

        XcodeCandidate device = Assert.Single(snapshot.Candidates, candidate => candidate.Kind == XcodeResourceKind.Device);
        XcodeCandidate runtime = Assert.Single(snapshot.Candidates, candidate => candidate.Kind == XcodeResourceKind.Runtime);
        Assert.False(device.CanSelect);
        Assert.False(runtime.CanSelect);
    }

    [Fact]
    public void NonObjectJsonRootReturnsWarningsWithoutThrowing()
    {
        XcodeSnapshot snapshot = XcodeJson.ParseInventory("[]", "{}", runtimeDeleteSupported: true);

        Assert.Empty(snapshot.Candidates);
        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Device);
        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Runtime);
    }

    [Fact]
    public void NonnumericDeviceSizePreservesSiblingWithUnknownSizeAndWarning()
    {
        const string simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Shutdown","dataPathSize":100},
              {"udid":"22222222-2222-4222-8222-222222222222","name":"iPhone 16 Pro","state":"Shutdown","dataPathSize":[]}]}}
            """;

        XcodeSnapshot snapshot = XcodeJson.ParseInventory(simctl, "{}", runtimeDeleteSupported: true);

        XcodeCandidate[] devices = snapshot.Candidates.Where(candidate => candidate.Kind == XcodeResourceKind.Device).ToArray();
        Assert.Equal(2, devices.Length);
        Assert.Equal(100, devices[0].SizeBytes);
        Assert.Null(devices[1].SizeBytes);
        Assert.All(devices, device => Assert.True(device.CanSelect));
        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Device);
    }
}
