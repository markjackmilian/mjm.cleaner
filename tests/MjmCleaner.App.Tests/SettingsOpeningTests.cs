using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless;
using Avalonia.Headless.XUnit;
using Avalonia.Input;
using Avalonia.VisualTree;
using MjmCleaner.App.Services;
using MjmCleaner.App.ViewModels;
using MjmCleaner.App.Views;
using MjmCleaner.Core.Settings;
using Xunit;

namespace MjmCleaner.App.Tests;

/// <summary>Il collegamento reale MainWindow, ViewModel e comando: i test sulla sola SettingsWindow non lo coprono.</summary>
public sealed class SettingsOpeningTests
{
    private static async Task<(MainWindow Window, MainWindowViewModel Vm)> CreateAsync()
    {
        string home = Path.Combine(Path.GetTempPath(), "mjm-cleaner-tests-" + Guid.NewGuid().ToString("N"));
        AppServices services = await AppServices.CreateAsync(new AppPaths(home));
        MainWindowViewModel vm = new(services);
        MainWindow window = new() { Width = 1120, Height = 700, DataContext = vm };
        window.Show();
        return (window, vm);
    }

    [AvaloniaFact]
    public async Task ShowSettingsCommandOpensTheModalSettingsWindow()
    {
        var (window, vm) = await CreateAsync();

        Task opening = vm.ShowSettingsCommand.ExecuteAsync(null);

        SettingsWindow settings = Assert.IsType<SettingsWindow>(Assert.Single(window.OwnedWindows));
        Assert.IsType<SettingsViewModel>(settings.DataContext);

        settings.Close();
        await opening;
        window.Close();
    }

    [AvaloniaFact]
    public async Task WhileTheWindowIsOpenTheCommandIsDisabled()
    {
        var (window, vm) = await CreateAsync();

        Task opening = vm.ShowSettingsCommand.ExecuteAsync(null);

        // Pulsante, ⌘, e voce di menu rispettano CanExecute: finché la finestra è aperta il comando è disabilitato.
        Assert.False(vm.ShowSettingsCommand.CanExecute(null));
        Assert.Single(window.OwnedWindows);

        window.OwnedWindows[0].Close();
        await opening;
        window.Close();
    }

    [AvaloniaFact]
    public async Task ClickingTheSidebarSettingsButtonOpensTheWindow()
    {
        var (window, _) = await CreateAsync();
        window.UpdateLayout();

        Button button = window.GetVisualDescendants().OfType<Button>()
            .Single(b => b.GetVisualDescendants().OfType<TextBlock>().Any(t => t.Text == "Impostazioni…"));
        Point center = button.TranslatePoint(new Point(button.Bounds.Width / 2, button.Bounds.Height / 2), window)!.Value;
        window.MouseDown(center, MouseButton.Left);
        window.MouseUp(center, MouseButton.Left);

        SettingsWindow settings = Assert.IsType<SettingsWindow>(Assert.Single(window.OwnedWindows));
        settings.Close();
        window.Close();
    }

    [AvaloniaFact]
    public async Task CommandCommaOpensTheWindow()
    {
        var (window, _) = await CreateAsync();
        window.UpdateLayout();
        window.Focus();

        window.KeyPress(Key.OemComma, RawInputModifiers.Meta, PhysicalKey.Comma, ",");

        SettingsWindow settings = Assert.IsType<SettingsWindow>(Assert.Single(window.OwnedWindows));
        settings.Close();
        window.Close();
    }

    /// <summary>
    /// Su macOS Avalonia legge il menu dell'applicazione una sola volta, subito dopo Initialize():
    /// una voce aggiunta più tardi non compare. Va quindi trovata già all'avvio, senza il ViewModel.
    /// </summary>
    [AvaloniaFact]
    public void TheApplicationMenuHasTheSettingsItemFromStartup()
    {
        App app = Assert.IsType<App>(Application.Current);

        NativeMenu menu = Assert.IsType<NativeMenu>(NativeMenu.GetMenu(app));

        NativeMenuItem item = Assert.IsType<NativeMenuItem>(Assert.Single(menu.Items));
        Assert.Same(app.SettingsMenuItem, item);
        Assert.Equal("Impostazioni…", item.Header);
        Assert.Equal(new KeyGesture(Key.OemComma, KeyModifiers.Meta), item.Gesture);
    }
}
