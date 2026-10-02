using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Headless.XUnit;
using Avalonia.Interactivity;
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

        window.Close();
    }

    [AvaloniaFact]
    public void ClosingTheWindowRestoresTheAppearance()
    {
        var (window, appearance) = Create();
        ((SettingsViewModel)window.DataContext!).IsDark = true;

        window.Close();

        Assert.Equal(AppearancePreference.Auto, appearance.Applied[^1]);
    }

    [AvaloniaFact]
    public void AppearanceCaptionSitsBelowTheCard()
    {
        var (window, _) = Create();

        TextBlock caption = Assert.Single(window.GetVisualDescendants().OfType<TextBlock>(),
            t => t.Text == "Automatico segue l'aspetto scelto in Impostazioni di Sistema.");
        // La didascalia segue la card come in tutte le altre sezioni: non ne è un discendente.
        Assert.DoesNotContain(caption.GetVisualAncestors().OfType<Border>(), b => b.Classes.Contains("SurfaceCard"));
        Assert.Contains("Caption", caption.Classes);
        Assert.Equal(11.5, caption.FontSize);
        Assert.Equal(new Avalonia.Thickness(4, 0), caption.Margin);

        window.Close();
    }

    [AvaloniaFact]
    public void NumericFieldsUseTheCompactStepperWithNamedButtons()
    {
        var (window, _) = Create();

        NumericUpDown[] fields = [.. window.GetVisualDescendants().OfType<NumericUpDown>()];
        Assert.Equal(4, fields.Length);
        foreach (NumericUpDown field in fields)
        {
            Assert.Contains("Compact", field.Classes);
            string fieldName = AutomationProperties.GetName(field) ?? string.Empty;
            Assert.False(string.IsNullOrWhiteSpace(fieldName));

            RepeatButton up = Assert.Single(field.GetVisualDescendants().OfType<RepeatButton>(), b => b.Name == "PART_IncreaseButton");
            RepeatButton down = Assert.Single(field.GetVisualDescendants().OfType<RepeatButton>(), b => b.Name == "PART_DecreaseButton");
            Assert.StartsWith("Aumenta ", AutomationProperties.GetName(up));
            Assert.StartsWith("Diminuisci ", AutomationProperties.GetName(down));
            Assert.EndsWith(fieldName[1..], AutomationProperties.GetName(up));
            Assert.EndsWith(fieldName[1..], AutomationProperties.GetName(down));

            // Stepper compatto: i due pulsanti stanno uno sopra l'altro e sono piccoli.
            Assert.True(down.Bounds.Top >= up.Bounds.Bottom - 0.5 && Equals(up.GetVisualParent(), down.GetVisualParent()));
            Assert.True(up.Bounds.Width <= 16 && up.Bounds.Height <= 12);
            Assert.Equal(64, field.GetVisualDescendants().OfType<Border>().Single(b => b.Name == "PART_Field").Bounds.Width, 1);
        }

        window.Close();
    }

    [AvaloniaFact]
    public void SteppingStillChangesTheBoundValueAndClamps()
    {
        var (window, _) = Create();
        SettingsViewModel vm = (SettingsViewModel)window.DataContext!;
        NumericUpDown field = window.GetVisualDescendants().OfType<NumericUpDown>().First();
        RepeatButton up = field.GetVisualDescendants().OfType<RepeatButton>().Single(b => b.Name == "PART_IncreaseButton");
        RepeatButton down = field.GetVisualDescendants().OfType<RepeatButton>().Single(b => b.Name == "PART_DecreaseButton");

        long before = vm.LargeFileThresholdMegabytes;
        up.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.Equal(before + 1, vm.LargeFileThresholdMegabytes);
        down.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.Equal(before, vm.LargeFileThresholdMegabytes);

        field.Value = 1;
        down.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Assert.Equal(1, vm.LargeFileThresholdMegabytes);

        window.Close();
    }

    [AvaloniaFact]
    public void AllSectionCaptionsUseTheSameSize()
    {
        var (window, _) = Create();

        TextBlock[] captions = [.. window.GetVisualDescendants().OfType<TextBlock>().Where(t => t.Classes.Contains("Caption"))];
        Assert.Equal(5, captions.Length);
        Assert.All(captions, c => Assert.Equal(11.5, c.FontSize));

        window.Close();
    }

    [AvaloniaFact]
    public void SelectedAppearancePreviewHasAnUnclippedAccentRing()
    {
        var (window, _) = Create();

        Border[] rings = [.. window.GetVisualDescendants().OfType<Border>().Where(b => b.Classes.Contains("Ring"))];
        Assert.Equal(3, rings.Length);
        // Automatico è selezionato per default: anello pieno da 2 px; gli altri hanno solo il filetto.
        Assert.Equal(2, rings[0].BoxShadow[0].Spread);
        Assert.Equal(0.5, rings[1].BoxShadow[0].Spread);
        Assert.Equal(0.5, rings[2].BoxShadow[0].Spread);
        // L'ombra non deve essere ritagliata dal Border che la disegna.
        Assert.All(rings, r => Assert.False(r.ClipToBounds));
        Assert.All(rings, r => Assert.True(((Border)r.Child!).ClipToBounds));

        window.Close();
    }

    [AvaloniaTheory]
    [InlineData(":pointerover")]
    [InlineData(":focus")]
    [InlineData(":disabled")]
    public void CompactFieldDoesNotPaintFluentTextBoxChrome(string pseudoClass)
    {
        var (window, _) = Create();
        TextBox box = window.GetVisualDescendants().OfType<NumericUpDown>().First().GetVisualDescendants().OfType<TextBox>().Single();
        ((IPseudoClasses)box.Classes).Set(pseudoClass, true);
        window.UpdateLayout();

        Border chrome = box.GetVisualDescendants().OfType<Border>().Single(b => b.Name == "PART_BorderElement");
        Assert.Equal(0, ((Avalonia.Media.ISolidColorBrush?)chrome.Background)?.Color.A ?? 0);
        Assert.Equal(0, ((Avalonia.Media.ISolidColorBrush?)chrome.BorderBrush)?.Color.A ?? 0);
        Assert.Equal(new Avalonia.Thickness(0), chrome.BorderThickness);

        window.Close();
    }
}
