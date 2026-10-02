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
    public void AppearanceDefaultsToAuto()
    {
        Assert.Equal(AppearancePreference.Auto, new CleanerSettings().Appearance);
    }

    [Fact]
    public void LegacyFileWithoutAppearanceLoadsAsAuto()
    {
        MockFileSystem fs = new();
        AppPaths paths = new(Home);
        fs.AddFile(paths.SettingsFile, new MockFileData("""{ "DownloadsMinAgeDays": 12 }"""));

        CleanerSettings settings = new SettingsStore(fs, paths).Load();

        Assert.Equal(12, settings.DownloadsMinAgeDays);
        Assert.Equal(AppearancePreference.Auto, settings.Appearance);
    }

    [Fact]
    public void AppearanceRoundTripsAsReadableString()
    {
        MockFileSystem fs = new();
        AppPaths paths = new(Home);
        SettingsStore store = new(fs, paths);

        store.Save(new CleanerSettings { Appearance = AppearancePreference.Dark });

        Assert.Contains("\"Appearance\": \"Dark\"", fs.File.ReadAllText(paths.SettingsFile));
        Assert.Equal(AppearancePreference.Dark, store.Load().Appearance);
    }

    [Theory]
    [InlineData("\"Darkk\"")]
    [InlineData("7")]
    [InlineData("-1")]
    [InlineData("null")]
    [InlineData("true")]
    [InlineData("\"\"")]
    [InlineData("\"1\"")]
    [InlineData("{ \"x\": 1 }")]
    [InlineData("[ \"Dark\" ]")]
    public void UnknownAppearanceValueFallsBackToAutoAndKeepsTheOtherSettings(string appearanceJson)
    {
        MockFileSystem fs = new();
        AppPaths paths = new(Home);
        fs.AddFile(paths.SettingsFile, new MockFileData("{ \"DownloadsMinAgeDays\": 12, \"Appearance\": " + appearanceJson + ", \"LogsMinAgeDays\": 5 }"));

        CleanerSettings settings = new SettingsStore(fs, paths).Load();

        Assert.Equal(AppearancePreference.Auto, settings.Appearance);
        Assert.Equal(12, settings.DownloadsMinAgeDays);
        Assert.Equal(5, settings.LogsMinAgeDays);
    }

    [Theory]
    [InlineData("dark", AppearancePreference.Dark)]
    [InlineData("DARK", AppearancePreference.Dark)]
    [InlineData("Light", AppearancePreference.Light)]
    [InlineData("auto", AppearancePreference.Auto)]
    public void AppearanceIsReadCaseInsensitively(string text, AppearancePreference expected)
    {
        MockFileSystem fs = new();
        AppPaths paths = new(Home);
        fs.AddFile(paths.SettingsFile, new MockFileData("{ \"Appearance\": \"" + text + "\" }"));

        Assert.Equal(expected, new SettingsStore(fs, paths).Load().Appearance);
    }

    [Theory]
    [InlineData(AppearancePreference.Auto)]
    [InlineData(AppearancePreference.Light)]
    [InlineData(AppearancePreference.Dark)]
    public void AppearanceRoundTripsForEveryValue(AppearancePreference preference)
    {
        MockFileSystem fs = new();
        AppPaths paths = new(Home);
        SettingsStore store = new(fs, paths);

        store.Save(new CleanerSettings { Appearance = preference, DownloadsMinAgeDays = 7 });

        Assert.Contains($"\"Appearance\": \"{preference}\"", fs.File.ReadAllText(paths.SettingsFile));
        CleanerSettings loaded = store.Load();
        Assert.Equal(preference, loaded.Appearance);
        Assert.Equal(7, loaded.DownloadsMinAgeDays);
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
