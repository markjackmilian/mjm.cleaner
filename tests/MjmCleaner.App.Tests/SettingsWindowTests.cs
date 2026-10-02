using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.VisualTree;
using MjmCleaner.App.Services;
using MjmCleaner.App.ViewModels;
using MjmCleaner.App.Views;
using MjmCleaner.Core.Settings;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class SettingsWindowTests
{
    private sealed class MemoryStore(CleanerSettings initial) : ISettingsStore
    {
        public CleanerSettings Load() => initial;
        public void Save(CleanerSettings settings) { }
    }

    private sealed class RecordingAppearance : IAppearanceController
    {
        public List<AppearancePreference> Applied { get; } = [];
        public void Apply(AppearancePreference preference) => Applied.Add(preference);
    }

    private sealed class NoPicker : IFolderPicker
    {
        public Task<string?> PickFolderAsync(string title) => Task.FromResult<string?>(null);
    }

    private static (SettingsWindow Window, RecordingAppearance Appearance) Create()
    {
        RecordingAppearance appearance = new();
        SettingsViewModel vm = new(new MemoryStore(new CleanerSettings()), appearance, new NoPicker(), () => { });
        SettingsWindow window = new() { DataContext = vm };
        window.Show();
        window.UpdateLayout();
        return (window, appearance);
    }

    [AvaloniaFact]
    public void ShowsTheFourSectionsAndTheEmptyFolderState()
    {
        var (window, _) = Create();

        string[] texts = [.. window.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text ?? "")];
        Assert.Contains("Aspetto", texts);
        Assert.Contains("Progetti .NET", texts);
        Assert.Contains("File grandi", texts);
        Assert.Contains("Età minima", texts);
        Assert.Contains("Nessuna cartella. Premi + per aggiungerne una.", texts);
        Assert.Equal(700, window.Width);
    }

    [AvaloniaFact]
    public void ClosingTheWindowRestoresTheAppearance()
    {
        var (window, appearance) = Create();
        ((SettingsViewModel)window.DataContext!).IsDark = true;

        window.Close();

        Assert.Equal(AppearancePreference.Auto, appearance.Applied[^1]);
    }
}
