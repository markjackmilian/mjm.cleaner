using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.Core.Tests.Settings;

public class SettingsStoreTests
{
    private const string Home = "/Users/tester";

    [Fact]
    public void LoadReturnsDefaultsWhenFileMissing()
    {
        MockFileSystem fs = new();
        SettingsStore store = new(fs, new AppPaths(Home));

        CleanerSettings settings = store.Load();

        Assert.Empty(settings.ProjectRoots);
        Assert.Equal(90, settings.DownloadsMinAgeDays);
        Assert.Equal(30, settings.LogsMinAgeDays);
        Assert.Equal(180, settings.NuGetMinAgeDays);
        Assert.Equal(500L * 1024 * 1024, settings.LargeFileThresholdBytes);
    }

    [Fact]
    public void SaveThenLoadRoundTrips()
    {
        MockFileSystem fs = new();
        SettingsStore store = new(fs, new AppPaths(Home));
        CleanerSettings original = new()
        {
            ProjectRoots = ["/Users/tester/projects"],
            DownloadsMinAgeDays = 30,
            SelectedCategoryIds = ["system-caches", "dev-caches"],
        };

        store.Save(original);
        CleanerSettings loaded = store.Load();

        Assert.Equal(["/Users/tester/projects"], loaded.ProjectRoots);
        Assert.Equal(30, loaded.DownloadsMinAgeDays);
        Assert.Equal(["system-caches", "dev-caches"], loaded.SelectedCategoryIds);
    }

    [Fact]
    public void LoadReturnsDefaultsWhenFileIsCorrupt()
    {
        MockFileSystem fs = new();
        AppPaths paths = new(Home);
        fs.AddFile(paths.SettingsFile, new MockFileData("{ questo non è json"));
        SettingsStore store = new(fs, paths);

        CleanerSettings settings = store.Load();

        Assert.Equal(90, settings.DownloadsMinAgeDays);
    }

    [Fact]
    public void AppPathsLiveUnderApplicationSupport()
    {
        AppPaths paths = new(Home);

        Assert.Equal("/Users/tester/Library/Application Support/mjm.cleaner", paths.SupportDirectory);
        Assert.EndsWith("history.db", paths.DatabaseFile);
        Assert.EndsWith("settings.json", paths.SettingsFile);
        Assert.EndsWith("logs", paths.LogsDirectory);
    }
}
