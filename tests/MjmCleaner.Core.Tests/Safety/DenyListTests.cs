using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Tests.Safety;

public class DenyListTests
{
    private const string Home = "/Users/tester";
    private static DenyList Create() => new(Home);

    [Theory]
    [InlineData("/System/Library/Fonts")]
    [InlineData("/usr/bin")]
    [InlineData("/bin")]
    [InlineData("/Applications/Safari.app")]
    [InlineData("/Users/tester")]
    [InlineData("/Users/tester/Documents")]
    [InlineData("/Users/tester/Documents/fatture/2026")]
    [InlineData("/Users/tester/Desktop")]
    [InlineData("/Users/tester/Library/Application Support/qualcosa")]
    [InlineData("/Users/tester/Library/Mobile Documents")]
    [InlineData("/Users/tester/.ssh/id_rsa")]
    [InlineData("/Users/tester/Library/Containers/com.docker.docker/Data")]
    public void DeniesProtectedPaths(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData("/Users/tester/Library/Caches/com.apple.Safari")]
    [InlineData("/Users/tester/Library/Logs/qualcosa.log")]
    [InlineData("/Library/Caches/com.apple.qualcosa")]
    [InlineData("/Library/Logs/DiagnosticReports/report.crash")]
    [InlineData("/Users/tester/.nuget/packages/newtonsoft.json")]
    [InlineData("/Users/tester/projects/app/bin")]
    public void AllowsCleanablePaths(string path)
    {
        Assert.False(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData("/Users/tester/documents/fatture")]
    [InlineData("/Users/TESTER/Documents")]
    [InlineData("/users/tester/.SSH/config")]
    public void DeniesRegardlessOfCase(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    [Fact]
    public void DeniesLibraryButAllowsItsCachesAndLogs()
    {
        DenyList list = Create();
        Assert.True(list.IsDenied("/Library/Preferences", out _));
        Assert.False(list.IsDenied("/Library/Caches/x", out _));
        Assert.False(list.IsDenied("/Library/Logs/x", out _));
    }

    [Fact]
    public void ReasonExplainsWhichRuleMatched()
    {
        Create().IsDenied("/Users/tester/Documents/x", out string reason);
        Assert.Contains("Documents", reason);
    }
}
