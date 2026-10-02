using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;

namespace MjmCleaner.App.ViewModels;

public sealed partial class MainWindowViewModel : ViewModelBase, IXcodeNavigation
{
    private readonly AppServices _services;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsXcodeBusy))]
    private object? _currentPage;

    [ObservableProperty]
    private string _totalFreedText = "—";

    public MainWindowViewModel(AppServices services)
    {
        _services = services;
        StartOver();
    }

    public AppServices Services => _services;
    public bool IsXcodeBusy => CurrentPage is XcodeViewModel { IsDeleting: true };

    partial void OnCurrentPageChanged(object? oldValue, object? newValue)
    {
        if (oldValue is XcodeViewModel previous) previous.PropertyChanged -= OnXcodePageChanged;
        if (newValue is XcodeViewModel current) current.PropertyChanged += OnXcodePageChanged;
        OnPropertyChanged(nameof(IsXcodeBusy));
        ShowHistoryCommand.NotifyCanExecuteChanged();
        ShowSettingsCommand.NotifyCanExecuteChanged();
        ShowDockerCommand.NotifyCanExecuteChanged();
        ShowXcodeCommand.NotifyCanExecuteChanged();
    }

    private void OnXcodePageChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(XcodeViewModel.IsDeleting))
        {
            OnPropertyChanged(nameof(IsXcodeBusy));
            ShowHistoryCommand.NotifyCanExecuteChanged();
            ShowSettingsCommand.NotifyCanExecuteChanged();
            ShowDockerCommand.NotifyCanExecuteChanged();
            ShowXcodeCommand.NotifyCanExecuteChanged();
        }
    }

    /// <summary>Naviga a una pagina.</summary>
    public void GoTo(object page) => CurrentPage = page;

    /// <summary>Torna al passo 1 del wizard: usato all'avvio e ogni volta che un ciclo si conclude o viene annullato.</summary>
    public void StartOver() => CurrentPage = new ChooseStepViewModel(_services, this);

    public async Task RefreshTotalAsync()
    {
        long total = await _services.History.GetTotalBytesFreedAsync(CancellationToken.None);
        TotalFreedText = $"{FormatBytes(total)} liberati finora";
    }

    private bool CanNavigateGlobally() => !IsXcodeBusy;

    [RelayCommand(CanExecute = nameof(CanNavigateGlobally))]
    private void ShowHistory() => CurrentPage = new HistoryViewModel(_services, this);

    [RelayCommand(CanExecute = nameof(CanNavigateGlobally))]
    private void ShowSettings() => CurrentPage = new SettingsViewModel(_services, this);

    [RelayCommand(CanExecute = nameof(CanNavigateGlobally))]
    private void ShowDocker() => CurrentPage = new DockerViewModel(_services, this);

    [RelayCommand(CanExecute = nameof(CanNavigateGlobally))]
    private void ShowXcode() => CurrentPage = new XcodeViewModel(_services.Xcode, _services.History, _services.SessionLog, this);
}
