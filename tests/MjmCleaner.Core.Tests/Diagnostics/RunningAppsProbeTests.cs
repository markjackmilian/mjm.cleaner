using MjmCleaner.Core.Diagnostics;

namespace MjmCleaner.Core.Tests.Diagnostics;

public class RunningAppsProbeTests
{
    private static RunningAppsProbe Create(params string[] processes)
        => new(() => processes);

    [Fact]
    public void MatchesBundleIdentifierAgainstProcessName()
    {
        IReadOnlyList<string> affected = Create("Safari", "Finder")
            .AffectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]);

        Assert.Equal(["Safari"], affected);
    }

    [Fact]
    public void IgnoresProcessesNotInvolved()
    {
        IReadOnlyList<string> affected = Create("Mail")
            .AffectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]);

        Assert.Empty(affected);
    }

    [Fact]
    public void ReportsEachApplicationOnlyOnce()
    {
        IReadOnlyList<string> affected = Create("Safari").AffectedApps(
        [
            "/Users/tester/Library/Caches/com.apple.Safari",
            "/Users/tester/Library/Caches/com.apple.Safari.WebKit",
        ]);

        Assert.Equal(["Safari"], affected);
    }

    [Fact]
    public void IgnoresVeryShortProcessNamesToAvoidFalsePositives()
    {
        IReadOnlyList<string> affected = Create("ls")
            .AffectedApps(["/Users/tester/Library/Caches/com.apple.Tools"]);

        Assert.Empty(affected);
    }
}
