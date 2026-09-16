using CommunityToolkit.Mvvm.ComponentModel;
using MjmCleaner.App.Services;

namespace MjmCleaner.App.ViewModels;

// Nota: l'using di CommunityToolkit.Mvvm.Input serve dal Task 21, quando arrivano i comandi
// della barra strumenti. Se il compilatore segnala un using inutilizzato, rimuoverlo ora e
// riaggiungerlo allora.
public sealed partial class MainWindowViewModel : ViewModelBase
{
    private readonly AppServices _services;

    [ObservableProperty]
    private object? _currentPage;

    [ObservableProperty]
    private string _totalFreedText = "—";

    public MainWindowViewModel(AppServices services) => _services = services;

    public AppServices Services => _services;

    /// <summary>Naviga a una pagina. Il Task 17 imposta qui il primo passo del wizard.</summary>
    public void GoTo(object page) => CurrentPage = page;

    public async Task RefreshTotalAsync()
    {
        long total = await _services.History.GetTotalBytesFreedAsync(CancellationToken.None);
        TotalFreedText = $"{FormatBytes(total)} liberati finora";
    }
}
