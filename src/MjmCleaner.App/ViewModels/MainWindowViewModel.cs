using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;

namespace MjmCleaner.App.ViewModels;

public sealed partial class MainWindowViewModel : ViewModelBase
{
    private readonly AppServices _services;

    [ObservableProperty]
    private object? _currentPage;

    [ObservableProperty]
    private string _totalFreedText = "—";

    public MainWindowViewModel(AppServices services)
    {
        _services = services;
        StartOver();
    }

    public AppServices Services => _services;

    /// <summary>Naviga a una pagina.</summary>
    public void GoTo(object page) => CurrentPage = page;

    /// <summary>Torna al passo 1 del wizard: usato all'avvio e ogni volta che un ciclo si conclude o viene annullato.</summary>
    public void StartOver() => CurrentPage = new ChooseStepViewModel(_services, this);

    public async Task RefreshTotalAsync()
    {
        long total = await _services.History.GetTotalBytesFreedAsync(CancellationToken.None);
        TotalFreedText = $"{FormatBytes(total)} liberati finora";
    }

    [RelayCommand]
    private void ShowHistory() => CurrentPage = new HistoryViewModel(_services, this);

    [RelayCommand]
    private void ShowSettings() => CurrentPage = new SettingsViewModel(_services, this);
}
