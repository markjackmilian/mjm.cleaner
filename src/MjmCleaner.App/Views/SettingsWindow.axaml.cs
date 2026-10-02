using Avalonia.Controls;
using MjmCleaner.App.ViewModels;

namespace MjmCleaner.App.Views;

public partial class SettingsWindow : Window
{
    private SettingsViewModel? _subscribed;

    public SettingsWindow()
    {
        InitializeComponent();
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (_subscribed is not null) _subscribed.CloseRequested -= OnCloseRequested;
        _subscribed = DataContext as SettingsViewModel;
        if (_subscribed is not null) _subscribed.CloseRequested += OnCloseRequested;
    }

    /// <summary>Altezza predefinita: il contenuto scorre, la barra azioni resta sempre visibile.</summary>
    private const double DefaultHeight = 680;

    /// <summary>Spazio lasciato libero rispetto all'area utile (barra dei menu, Dock, bordi).</summary>
    private const double ScreenMargin = 40;

    private const double MinimumHeight = 400;

    /// <summary>Altezza richiesta, ridotta all'area utile dello schermo ma mai sotto una soglia utilizzabile.</summary>
    public static double FitHeight(double requested, double workingAreaHeight, double margin)
        => Math.Max(MinimumHeight, Math.Min(requested, workingAreaHeight - margin));

    /// <summary>Su schermi da 13" l'area utile è circa 815 pt: la finestra non deve uscirne.</summary>
    protected override void OnOpened(EventArgs e)
    {
        base.OnOpened(e);
        Avalonia.Platform.Screen? screen = Screens.ScreenFromWindow(this);
        if (screen is null) return;

        double available = screen.WorkingArea.Height / screen.Scaling;
        Height = FitHeight(DefaultHeight, available, ScreenMargin);
    }

    private void OnCloseRequested(object? sender, EventArgs e) => Close();

    /// <summary>Ogni chiusura senza Salva (Annulla o pulsante rosso) ripristina l'aspetto di prima.</summary>
    protected override void OnClosed(EventArgs e)
    {
        (DataContext as SettingsViewModel)?.Dismiss();
        base.OnClosed(e);
    }
}
