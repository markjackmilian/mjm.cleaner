using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Microsoft.Data.Sqlite;
using MjmCleaner.App.Services;
using MjmCleaner.App.ViewModels;
using MjmCleaner.App.Views;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App;

public partial class App : Application
{
    public App()
    {
        // Il menu nativo macOS viene creato prima di Initialize(): impostare il nome anche nel
        // costruttore evita che l'avvio non impacchettato conservi "Avalonia Application".
        Name = "mjm.cleaner";
    }

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override async void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            Window mainWindow = await CreateMainWindowAsync();
            desktop.MainWindow = mainWindow;

            if (mainWindow is MainWindow { DataContext: MainWindowViewModel viewModel })
            {
                await viewModel.RefreshTotalAsync();
            }
        }

        base.OnFrameworkInitializationCompleted();
    }

    /// <summary>
    /// Se la composizione dei servizi fallisce (cartella dati non scrivibile, database corrotto)
    /// l'eccezione non deve propagare fino in cima: chi avvia il bundle .app vedrebbe solo la
    /// finestra non aprirsi, senza spiegazioni. Si mostra invece una finestra minima che dice
    /// cosa è andato storto e dove, così l'utente può intervenire.
    /// </summary>
    private static async Task<Window> CreateMainWindowAsync()
    {
        try
        {
            AppServices services = await AppServices.CreateAsync();
            return new MainWindow { DataContext = new MainWindowViewModel(services) };
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or SqliteException)
        {
            AppPaths paths = AppPaths.ForCurrentUser();
            string message =
                $"Percorso: {paths.SupportDirectory}{Environment.NewLine}{Environment.NewLine}Motivo: {ex.Message}";
            return new FatalErrorWindow(message);
        }
    }
}
