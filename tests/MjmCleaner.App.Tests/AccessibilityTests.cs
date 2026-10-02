using Avalonia.Automation;
using Avalonia.Automation.Peers;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Headless.XUnit;
using Avalonia.VisualTree;
using MjmCleaner.App.Services;
using MjmCleaner.App.ViewModels;
using MjmCleaner.App.Views;
using MjmCleaner.Core.Settings;
using Xunit;

namespace MjmCleaner.App.Tests;

/// <summary>Ogni pulsante deve avere un nome per le tecnologie assistive: mai il nome del tipo del contenitore.</summary>
public sealed class AccessibilityTests
{
    private sealed class MemoryStore(CleanerSettings initial) : ISettingsStore
    {
        public CleanerSettings Load() => initial;
        public void Save(CleanerSettings settings) { }
    }

    private sealed class NoAppearance : IAppearanceController
    {
        public void Apply(AppearancePreference preference) { }
    }

    private sealed class NoPicker : IFolderPicker
    {
        public Task<string?> PickFolderAsync(string title) => Task.FromResult<string?>(null);
    }

    private static void AssertEveryButtonIsNamed(Control root, params string[] required)
    {
        // Gli elementi decorativi (es. la casella dentro la riga, già annunciata dalla riga) sono esclusi dalla vista di accessibilità.
        Control[] buttons = [.. root.GetVisualDescendants().OfType<Control>().Where(c =>
            c is Button or ToggleButton or RadioButton
            && AutomationProperties.GetAccessibilityView(c) != AccessibilityView.Raw)];
        Assert.NotEmpty(buttons);

        List<string> names = [];
        foreach (Control button in buttons)
        {
            string name = ControlAutomationPeer.CreatePeerForElement(button).GetName();
            Assert.False(string.IsNullOrWhiteSpace(name), $"{button.GetType().Name} senza nome accessibile");
            Assert.False(name.StartsWith("Avalonia.", StringComparison.Ordinal), $"{button.GetType().Name} ha il nome «{name}»");
            names.Add(name);
        }

        foreach (string expected in required) Assert.Contains(expected, names);
    }

    [AvaloniaFact]
    public async Task MainWindowButtonsHaveAccessibleNames()
    {
        using TestHome home = await TestHome.CreateAsync();
        MainWindow window = new() { Width = 1120, Height = 700, DataContext = new MainWindowViewModel(home.Services) };
        window.Show();
        window.UpdateLayout();

        AssertEveryButtonIsNamed(window, "Pulizia", "Docker", "Xcode", "Storico", "Impostazioni…");

        window.Close();
    }

    [AvaloniaFact]
    public async Task ChooseStepButtonsHaveAccessibleNames()
    {
        using TestHome home = await TestHome.CreateAsync();
        MainWindowViewModel main = new(home.Services);
        Window window = new() { Width = 888, Height = 700, Content = new ChooseStepView { DataContext = new ChooseStepViewModel(home.Services, main) } };
        window.Show();
        window.UpdateLayout();

        AssertEveryButtonIsNamed(window, "Analizza");

        window.Close();
    }

    [AvaloniaFact]
    public void SettingsWindowButtonsHaveAccessibleNames()
    {
        SettingsViewModel vm = new(new MemoryStore(new CleanerSettings()), new NoAppearance(), new NoPicker(), () => { });
        SettingsWindow window = new() { DataContext = vm };
        window.Show();
        window.UpdateLayout();

        AssertEveryButtonIsNamed(window, "Annulla", "Salva", "Automatico", "Chiaro", "Scuro");

        window.Close();
    }
}
