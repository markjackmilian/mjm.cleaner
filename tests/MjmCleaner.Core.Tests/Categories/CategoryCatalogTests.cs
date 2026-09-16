using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.Core.Tests.Categories;

public class CategoryCatalogTests
{
    private static readonly PathExpander Expander = new("/Users/tester", "/var/folders/ab/T");

    private static IReadOnlyList<CleanupCategory> Build(CleanerSettings? settings = null)
        => CategoryCatalog.Build(settings ?? new CleanerSettings(), Expander);

    [Fact]
    public void DefinesTheSixCategories()
    {
        string[] ids = [.. Build().Select(c => c.Id)];

        Assert.Equal(
            ["system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash-downloads-large"],
            ids);
    }

    [Fact]
    public void NuGetIsNestedUnderDevCachesAndNotSelectedByDefault()
    {
        CleanupCategory nuget = Build().Single(c => c.Id == "nuget-packages");

        Assert.Equal("dev-caches", nuget.ParentId);
        Assert.False(nuget.SelectedByDefault);
    }

    [Fact]
    public void HighRiskCategoryIsNeverSelectedByDefault()
    {
        CleanupCategory risky = Build().Single(c => c.Id == "trash-downloads-large");

        Assert.Equal(RiskLevel.High, risky.Risk);
        Assert.False(risky.SelectedByDefault);
    }

    [Fact]
    public void RuleRootsAreAlreadyExpanded()
    {
        CleanupCategory caches = Build().Single(c => c.Id == "system-caches");

        Assert.Contains(caches.Rules, r => r.Root == "/Users/tester/Library/Caches");
        Assert.Contains(caches.Rules, r => r.Root == "/Library/Caches");
        Assert.DoesNotContain(caches.Rules, r => r.Root.StartsWith('~'));
    }

    [Fact]
    public void ProjectBuildOutputHasOneRulePerConfiguredRoot()
    {
        CleanerSettings settings = new()
        {
            ProjectRoots = ["/Users/tester/projects", "/Users/tester/lavoro"],
        };

        CleanupCategory projects = Build(settings).Single(c => c.Id == "project-build-output");

        Assert.Equal(2, projects.Rules.Count);
        Assert.All(projects.Rules, r => Assert.True(r.RequiresProjectMarker));
        Assert.All(projects.Rules, r => Assert.Equal(ScanMode.MatchingDirs, r.Mode));
        Assert.All(projects.Rules, r => Assert.Equal(["bin", "obj"], r.IncludeGlobs));
    }

    [Fact]
    public void ProjectBuildOutputHasNoRulesWhenNoRootConfigured()
        => Assert.Empty(Build().Single(c => c.Id == "project-build-output").Rules);

    [Fact]
    public void AgeThresholdsComeFromSettings()
    {
        CleanerSettings settings = new() { LogsMinAgeDays = 7, DownloadsMinAgeDays = 45, NuGetMinAgeDays = 60 };
        IReadOnlyList<CleanupCategory> categories = Build(settings);

        CleanupRule logRule = categories.Single(c => c.Id == "logs").Rules[0];
        CleanupRule downloadsRule = categories
            .Single(c => c.Id == "trash-downloads-large").Rules
            .Single(r => r.Root == "/Users/tester/Downloads");
        CleanupRule nugetRule = categories.Single(c => c.Id == "nuget-packages").Rules[0];

        Assert.Equal(TimeSpan.FromDays(7), logRule.MinAge);
        Assert.Equal(TimeSpan.FromDays(45), downloadsRule.MinAge);
        Assert.Equal(TimeSpan.FromDays(60), nugetRule.MinAge);
    }

    [Fact]
    public void DockerIsNotReferencedByAnyRule()
    {
        Assert.DoesNotContain(
            Build().SelectMany(c => c.Rules),
            r => r.Root.Contains("docker", StringComparison.OrdinalIgnoreCase));
    }
}
