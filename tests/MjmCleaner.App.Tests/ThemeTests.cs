using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Media;
using Avalonia.Styling;
using MjmCleaner.App.Services;
using MjmCleaner.App.Views;
using MjmCleaner.Core.Settings;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class ThemeTests
{
    [Theory]
    [InlineData(AppearancePreference.Auto, "Default")]
    [InlineData(AppearancePreference.Light, "Light")]
    [InlineData(AppearancePreference.Dark, "Dark")]
    public void PreferenceMapsToThemeVariant(AppearancePreference preference, string expected)
        => Assert.Equal(expected, AppearanceController.ThemeVariantFor(preference).Key.ToString());

    [AvaloniaTheory]
    [InlineData("Light", "#FFF7F7F9")]
    [InlineData("Dark", "#FF1E1E20")]
    public void ContentTokenFollowsVariant(string variant, string expected)
    {
        ThemeVariant theme = variant == "Dark" ? ThemeVariant.Dark : ThemeVariant.Light;
        Assert.True(Application.Current!.TryGetResource("ContentBrush", theme, out object? value));
        Assert.Equal(expected, ((ISolidColorBrush)value!).Color.ToString().ToUpperInvariant());
    }

    // Gli alias temporanei usati dalle view non ancora migrate devono seguire il tema.
    [AvaloniaTheory]
    [InlineData("Light", "CardBrush", "#FFFFFFFF")]
    [InlineData("Dark", "CardBrush", "#FF2B2B2E")]
    [InlineData("Light", "CanvasBrush", "#FFF7F7F9")]
    [InlineData("Dark", "CanvasBrush", "#FF1E1E20")]
    [InlineData("Light", "ToolbarBrush", "#FFFFFFFF")]
    [InlineData("Dark", "ToolbarBrush", "#FF232325")]
    [InlineData("Light", "BorderBrush", "#14000000")]
    [InlineData("Dark", "BorderBrush", "#14FFFFFF")]
    [InlineData("Light", "SubtleSurfaceBrush", "#0E000000")]
    [InlineData("Dark", "SubtleSurfaceBrush", "#14FFFFFF")]
    public void LegacyAliasesFollowVariant(string variant, string key, string expected)
    {
        ThemeVariant theme = variant == "Dark" ? ThemeVariant.Dark : ThemeVariant.Light;
        Assert.True(Application.Current!.TryGetResource(key, theme, out object? value));
        Color color = ((ISolidColorBrush)value!).Color;
        // Color.ToString() usa il nome per i colori noti ("White"): si confronta l'ARGB esplicito.
        Assert.Equal(expected, $"#{color.A:X2}{color.R:X2}{color.G:X2}{color.B:X2}");
    }

    [AvaloniaFact]
    public void ApplySetsApplicationVariant()
    {
        AppearanceController controller = new(Application.Current!);
        try
        {
            controller.Apply(AppearancePreference.Dark);
            Assert.Equal(ThemeVariant.Dark, Application.Current!.RequestedThemeVariant);
            controller.Apply(AppearancePreference.Auto);
            Assert.Equal(ThemeVariant.Default, Application.Current!.RequestedThemeVariant);
        }
        finally
        {
            // Lo stato è globale all'applicazione di test: non va lasciato Dark agli altri test.
            Application.Current!.RequestedThemeVariant = ThemeVariant.Default;
        }
    }

    [AvaloniaFact]
    public void IconGeometriesAreRegistered()
    {
        foreach (string key in new[] { "IconSparkle", "IconCube", "IconHammer", "IconClock", "IconGear", "IconShield", "IconChevronRight", "IconPlus", "IconMinus", "IconCheck" })
        {
            Assert.True(Application.Current!.TryGetResource(key, ThemeVariant.Light, out object? value), key);
            Assert.IsAssignableFrom<Geometry>(value);
        }
    }

    [AvaloniaFact]
    public void StepIndicatorMarksOnlyTheCurrentStep()
    {
        StepIndicator indicator = new() { CurrentStep = 3 };
        Window window = new() { Content = indicator };
        try
        {
            window.Show();

            Assert.DoesNotContain("current", indicator.FindControl<Control>("Step1")!.Classes);
            Assert.Contains("current", indicator.FindControl<Control>("Step3")!.Classes);
            Assert.Contains("current", indicator.FindControl<Control>("Label3")!.Classes);

            indicator.CurrentStep = 2;
            Assert.DoesNotContain("current", indicator.FindControl<Control>("Step3")!.Classes);
            Assert.Contains("current", indicator.FindControl<Control>("Step2")!.Classes);
            Assert.DoesNotContain("current", indicator.FindControl<Control>("Label3")!.Classes);
        }
        finally
        {
            window.Close();
        }
    }
}
