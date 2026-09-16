using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Tests.Safety;

public class PathGuardTests
{
    private const string Home = "/Users/tester";
    private const string CacheRoot = "/Users/tester/Library/Caches";

    private static PathGuard Create(params string[] symlinks)
        => new(new DenyList(Home), new FakeLinkInspector(symlinks), Home);

    [Fact]
    public void AllowsItemInsideDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/com.apple.Safari", CacheRoot);
        Assert.True(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesItemOutsideDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate("/Users/tester/projects/app/bin", CacheRoot);
        Assert.False(verdict.IsAllowed);
        Assert.Contains("contenimento", verdict.Reason);
    }

    [Fact]
    public void DeniesTraversalEscapingDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/../../Documents/fatture", CacheRoot);
        Assert.False(verdict.IsAllowed);
    }

    [Fact]
    public void CanonicalizesBeforeComparing()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/./sub/../sub/file", CacheRoot);
        Assert.True(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesDeniedPathEvenWhenInsideDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate($"{Home}/Documents/x", Home);
        Assert.False(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesHomeItself()
    {
        Assert.False(Create().Validate(Home, Home).IsAllowed);
    }

    [Fact]
    public void DeniesDirectChildOfHome()
    {
        GuardVerdict verdict = Create().Validate($"{Home}/Downloads", $"{Home}/Downloads");
        Assert.False(verdict.IsAllowed);
        Assert.Contains("profondità", verdict.Reason);
    }

    [Fact]
    public void AllowsGrandchildOfHome()
    {
        Assert.True(Create().Validate($"{Home}/Downloads/vecchio.dmg", $"{Home}/Downloads").IsAllowed);
    }

    [Fact]
    public void AllowsSymlinkItselfSoTheLinkCanBeRemoved()
    {
        PathGuard guard = Create($"{CacheRoot}/collegamento");
        Assert.True(guard.Validate($"{CacheRoot}/collegamento", CacheRoot).IsAllowed);
    }

    [Fact]
    public void DeniesItemWhoseAncestorIsSymlink()
    {
        PathGuard guard = Create($"{CacheRoot}/collegamento");
        GuardVerdict verdict = guard.Validate($"{CacheRoot}/collegamento/vittima.txt", CacheRoot);
        Assert.False(verdict.IsAllowed);
        Assert.Contains("collegamento", verdict.Reason);
    }

    [Fact]
    public void DeniesRegardlessOfCase()
    {
        Assert.False(Create().Validate($"{Home}/documents/x", Home).IsAllowed);
    }

    [Fact]
    public void DeniesDockerContainer()
    {
        string docker = $"{Home}/Library/Containers/com.docker.docker/Data/vms";
        Assert.False(Create().Validate(docker, $"{Home}/Library/Containers").IsAllowed);
    }

    // I tre casi seguenti nascono dalla revisione del Task 3, che li aveva misurati
    // come passanti: la radice si riduceva a stringa vuota e sfuggiva a ogni confronto.
    [Theory]
    [InlineData("/")]
    [InlineData("//")]
    public void DeniesFilesystemRoot(string root)
    {
        Assert.False(Create().Validate(root, "/").IsAllowed);
    }

    [Fact]
    public void DeniesAnotherUsersHome()
    {
        Assert.False(Create().Validate("/Users/altro/Documents/fatture", "/Users").IsAllowed);
    }

    [Fact]
    public void DeniesExternalVolume()
    {
        Assert.False(Create().Validate("/Volumes/Backup/2026", "/Volumes").IsAllowed);
    }
}
