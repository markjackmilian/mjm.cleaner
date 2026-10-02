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

    private void OnCloseRequested(object? sender, EventArgs e) => Close();

    /// <summary>Ogni chiusura senza Salva (Annulla o pulsante rosso) ripristina l'aspetto di prima.</summary>
    protected override void OnClosed(EventArgs e)
    {
        (DataContext as SettingsViewModel)?.Dismiss();
        base.OnClosed(e);
    }
}
