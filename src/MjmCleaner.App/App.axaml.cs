using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Input;
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

    /// <summary>
    /// Voce «Impostazioni…» del menu dell'applicazione. Senza comando né gestori di clic resta disabilitata:
    /// il comando arriva quando esiste il ViewModel della finestra principale.
    /// </summary>
    public NativeMenuItem SettingsMenuItem { get; } = new("Impostazioni…") { Gesture = new KeyGesture(Key.OemComma, KeyModifiers.Meta) };

    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);

        // Su macOS il menu dell'applicazione è quello impostato qui: Avalonia lo legge una sola volta, appena
        // dopo Initialize(), e se non c'è lo sostituisce con il menu predefinito («About Avalonia»). Impostarlo
        // più tardi, per esempio in OnFrameworkInitializationCompleted, non ha alcun effetto sul menu mostrato.
        // Voci standard (Servizi, Nascondi, Esci) vengono accodate da Avalonia a questo menu.
        NativeMenu.SetMenu(this, new NativeMenu { SettingsMenuItem });
    }

    public override async void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            Window mainWindow = await CreateMainWindowAsync();
            desktop.MainWindow = mainWindow;

            if (mainWindow is MainWindow { DataContext: MainWindowViewModel viewModel })
            {
                // Il comando rispetta CanExecute: ⌘, e la voce di menu si disabilitano durante l'eliminazione di Xcode.
                SettingsMenuItem.Command = viewModel.ShowSettingsCommand;
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
            // L'aspetto va applicato prima di creare la finestra, così non lampeggia il tema sbagliato.
            new AppearanceController(Current!).Apply(services.Settings.Load().Appearance);
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
