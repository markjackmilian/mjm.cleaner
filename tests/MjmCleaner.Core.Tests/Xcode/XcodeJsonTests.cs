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
}
