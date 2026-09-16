using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;

namespace MjmCleaner.App.Views;

/// <summary>
/// Finestra di ultima istanza, mostrata quando la composizione dei servizi fallisce all'avvio
/// (dati inaccessibili o corrotti) e nessun'altra finestra dell'applicazione può aprirsi.
/// Costruita in codice, senza AXAML e senza dipendere da <see cref="Services.AppServices"/>:
/// deve funzionare anche quando ciò che dovrebbe comporla è compromesso.
/// </summary>
public sealed class FatalErrorWindow : Window
{
    public FatalErrorWindow(string message)
    {
        Title = "mjm.cleaner";
        Width = 480;
        SizeToContent = SizeToContent.Height;
        CanResize = false;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        Button closeButton = new()
        {
            Content = "Chiudi",
            HorizontalAlignment = HorizontalAlignment.Right,
            Padding = new Thickness(18, 8),
        };
        closeButton.Click += (_, _) => Close();

        Content = new StackPanel
        {
            Margin = new Thickness(24),
            Spacing = 16,
            Children =
            {
                new TextBlock
                {
                    Text = "Impossibile accedere ai dati dell'applicazione",
                    FontSize = 18,
                    FontWeight = FontWeight.Bold,
                    TextWrapping = TextWrapping.Wrap,
                },
                new TextBlock
                {
                    Text = message,
                    TextWrapping = TextWrapping.Wrap,
                },
                closeButton,
            },
        };
    }
}
