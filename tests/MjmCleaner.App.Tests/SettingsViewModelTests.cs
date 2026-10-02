using MjmCleaner.App.Services;
using MjmCleaner.App.ViewModels;
using MjmCleaner.Core.Settings;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class SettingsViewModelTests
{
    private sealed class MemoryStore(CleanerSettings initial) : ISettingsStore
    {
        public CleanerSettings Current { get; private set; } = initial;
        public int Saves { get; private set; }
        public CleanerSettings Load() => Current;
        public void Save(CleanerSettings settings) { Current = settings; Saves++; }
    }

    private sealed class RecordingAppearance : IAppearanceController
    {
        public List<AppearancePreference> Applied { get; } = [];
        public void Apply(AppearancePreference preference) => Applied.Add(preference);
    }

    private sealed class FixedPicker(string? result) : IFolderPicker
    {
        public Task<string?> PickFolderAsync(string title) => Task.FromResult(result);
    }

    private static (SettingsViewModel Vm, MemoryStore Store, RecordingAppearance Appearance, List<string> Events) Create(
        CleanerSettings? settings = null, string? picked = null)
    {
        MemoryStore store = new(settings ?? new CleanerSettings());
        RecordingAppearance appearance = new();
        List<string> events = [];
        SettingsViewModel vm = new(store, appearance, new FixedPicker(picked), () => events.Add("saved"));
        vm.CloseRequested += (_, _) => events.Add("close");
        return (vm, store, appearance, events);
    }

    [Fact]
    public void PickingAnAppearancePreviewsItImmediately()
    {
        var (vm, store, appearance, _) = Create();
        vm.IsDark = true;
        Assert.Equal(AppearancePreference.Dark, vm.Appearance);
        Assert.Equal([AppearancePreference.Dark], appearance.Applied);
        Assert.Equal(0, store.Saves);
    }

    [Fact]
    public void CancelRestoresTheLoadedAppearanceAndCloses()
    {
        var (vm, store, appearance, events) = Create(new CleanerSettings { Appearance = AppearancePreference.Light });
        vm.IsDark = true;
        vm.CancelCommand.Execute(null);
        Assert.Equal(AppearancePreference.Light, appearance.Applied[^1]);
        Assert.Equal(["close"], events);
        Assert.Equal(0, store.Saves);
    }

    [Fact]
    public void ClosingFromTheTitleBarBehavesLikeCancel()
    {
        var (vm, _, appearance, _) = Create();
        vm.IsLight = true;
        vm.Dismiss();
        Assert.Equal(AppearancePreference.Auto, appearance.Applied[^1]);
    }

    [Fact]
    public void SavePersistsAppearanceAndFoldersThenReturnsToStart()
    {
        var (vm, store, appearance, events) = Create(new CleanerSettings { ProjectRoots = ["~/src"] });
        vm.IsDark = true;
        vm.SaveCommand.Execute(null);
        vm.Dismiss();
        Assert.Equal(AppearancePreference.Dark, store.Current.Appearance);
        Assert.Equal(["~/src"], store.Current.ProjectRoots);
        Assert.Equal(["saved", "close"], events);
        Assert.Equal(AppearancePreference.Dark, appearance.Applied[^1]);
    }

    [Fact]
    public async Task AddingAFolderAppendsAndSelectsIt()
    {
        var (vm, _, _, _) = Create(picked: "/Users/tester/projects");
        await vm.AddProjectRootCommand.ExecuteAsync(null);
        Assert.Equal(["/Users/tester/projects"], vm.ProjectRoots);
        Assert.Equal("/Users/tester/projects", vm.SelectedProjectRoot);
    }

    [Fact]
    public async Task CancelledPickerAddsNothingAndDuplicatesAreNotRepeated()
    {
        var (vm, _, _, _) = Create(new CleanerSettings { LargeFileRoots = ["/Volumes/Data"] }, picked: "/Volumes/Data");
        await vm.AddLargeFileRootCommand.ExecuteAsync(null);
        Assert.Equal(["/Volumes/Data"], vm.LargeFileRoots);

        var (empty, _, _, _) = Create(picked: null);
        await empty.AddLargeFileRootCommand.ExecuteAsync(null);
        Assert.Empty(empty.LargeFileRoots);
    }

    [Fact]
    public void RemoveIsDisabledWithoutSelection()
    {
        var (vm, _, _, _) = Create(new CleanerSettings { ProjectRoots = ["/a", "/b"] });
        Assert.False(vm.RemoveProjectRootCommand.CanExecute(null));
        vm.SelectedProjectRoot = "/a";
        Assert.True(vm.RemoveProjectRootCommand.CanExecute(null));
        vm.RemoveProjectRootCommand.Execute(null);
        Assert.Equal(["/b"], vm.ProjectRoots);
        Assert.False(vm.RemoveProjectRootCommand.CanExecute(null));
    }

    [Fact]
    public void UnchangedThresholdKeepsExactBytes()
    {
        long bytes = 500L * 1024 * 1024 + 123;
        var (vm, store, _, _) = Create(new CleanerSettings { LargeFileThresholdBytes = bytes });
        vm.SaveCommand.Execute(null);
        Assert.Equal(bytes, store.Current.LargeFileThresholdBytes);
    }
}
