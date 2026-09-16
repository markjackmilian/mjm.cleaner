using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Tests.Safety;

namespace MjmCleaner.Core.Tests.Scanning;

public class MatchingDirsTests
{
    private const string Home = "/Users/tester";
    private const string Projects = "/Users/tester/projects";
    private static readonly DateTimeOffset Now = new(2026, 9, 15, 12, 0, 0, TimeSpan.Zero);

    private static RuleScanner Create(MockFileSystem fs, params string[] symlinks)
    {
        FakeLinkInspector links = new(symlinks);
        return new RuleScanner(fs, new PathGuard(new DenyList(Home), links, Home), links, new TestTimeProvider(Now));
    }

    private static CleanupRule BinObjRule(string root = Projects)
        => new(root, ScanMode.MatchingDirs, ["bin", "obj"], [], RequiresProjectMarker: true);

    [Fact]
    public void FindsBinAndObjNextToProjectFile()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/app/app.csproj", new MockFileData("<Project/>"));
        fs.AddFile($"{Projects}/app/bin/Debug/app.dll", new MockFileData(new byte[500]));
        fs.AddFile($"{Projects}/app/obj/project.assets.json", new MockFileData(new byte[100]));

        RuleScanOutcome outcome = Create(fs).Scan(BinObjRule(), CancellationToken.None);

        Assert.Equal(2, outcome.Items.Count);
        Assert.Contains(outcome.Items, i => i.Path == $"{Projects}/app/bin" && i.SizeBytes == 500);
        Assert.Contains(outcome.Items, i => i.Path == $"{Projects}/app/obj" && i.SizeBytes == 100);
    }

    [Fact]
    public void SkipsBinWithoutProjectFileAlongside()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/strumenti/bin/attrezzo", new MockFileData(new byte[10]));

        RuleScanOutcome outcome = Create(fs).Scan(BinObjRule(), CancellationToken.None);

        Assert.Empty(outcome.Items);
    }

    [Fact]
    public void RecognisesEveryProjectFileExtension()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/a/a.fsproj", new MockFileData("x"));
        fs.AddFile($"{Projects}/a/bin/x", new MockFileData(new byte[1]));
        fs.AddFile($"{Projects}/b/b.sln", new MockFileData("x"));
        fs.AddFile($"{Projects}/b/bin/x", new MockFileData(new byte[1]));
        fs.AddFile($"{Projects}/c/c.vbproj", new MockFileData("x"));
        fs.AddFile($"{Projects}/c/bin/x", new MockFileData(new byte[1]));

        RuleScanOutcome outcome = Create(fs).Scan(BinObjRule(), CancellationToken.None);

        Assert.Equal(3, outcome.Items.Count);
    }

    [Fact]
    public void DoesNotDescendIntoAFoundDirectory()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/app/app.csproj", new MockFileData("x"));
        fs.AddFile($"{Projects}/app/bin/annidato/bin/x.dll", new MockFileData(new byte[10]));

        RuleScanOutcome outcome = Create(fs).Scan(BinObjRule(), CancellationToken.None);

        Assert.Equal($"{Projects}/app/bin", outcome.Items.Single().Path);
    }

    [Fact]
    public void WithoutMarkerRequirementFindsDirectoriesByName()
    {
        MockFileSystem fs = new();
        string nuget = $"{Home}/.nuget/packages";
        fs.AddFile($"{nuget}/newtonsoft.json/13.0.3/pacchetto.nupkg", new MockFileData(new byte[42]));

        CleanupRule rule = new(nuget, ScanMode.MatchingDirs, ["*"], [], MaxDepth: 1);
        RuleScanOutcome outcome = Create(fs).Scan(rule, CancellationToken.None);

        Assert.Equal($"{nuget}/newtonsoft.json", outcome.Items.Single().Path);
    }

    [Fact]
    public void HonoursMaxDepth()
    {
        MockFileSystem fs = new();
        string nuget = $"{Home}/.nuget/packages";
        fs.AddFile($"{nuget}/pacchetto/1.0.0/dentro/file.bin", new MockFileData(new byte[5]));

        CleanupRule rule = new(nuget, ScanMode.MatchingDirs, ["*"], [], MaxDepth: 1);
        RuleScanOutcome outcome = Create(fs).Scan(rule, CancellationToken.None);

        Assert.Single(outcome.Items);
        Assert.Equal($"{nuget}/pacchetto", outcome.Items.Single().Path);
    }

    [Fact]
    public void DoesNotFollowSymlinkedDirectories()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/collegamento/app.csproj", new MockFileData("x"));
        fs.AddFile($"{Projects}/collegamento/bin/x.dll", new MockFileData(new byte[10]));

        RuleScanOutcome outcome = Create(fs, $"{Projects}/collegamento").Scan(BinObjRule(), CancellationToken.None);

        Assert.Empty(outcome.Items);
    }
}
