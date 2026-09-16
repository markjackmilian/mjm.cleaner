using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.App.ViewModels;

public sealed partial class CategoryProgress(string displayName) : ObservableObject
{
    [ObservableProperty]
    private string _status = "in attesa";

    public string DisplayName { get; } = displayName;
}

public sealed partial class ScanStepViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;
    private readonly IReadOnlyList<CleanupCategory> _categories;
    private readonly CancellationTokenSource _cts = new();

    [ObservableProperty]
    private string _currentPath = string.Empty;

    [ObservableProperty]
    private bool _isRunning = true;

    public ScanStepViewModel(
        AppServices services,
        MainWindowViewModel main,
        IReadOnlyList<CleanupCategory> categories)
    {
        _services = services;
        _main = main;
        _categories = categories;

        Progress = [.. categories.Select(c => new CategoryProgress(c.DisplayName))];
        _ = RunAsync();
    }

    public ObservableCollection<CategoryProgress> Progress { get; }

    private async Task RunAsync()
    {
        Progress<ScanProgress> reporter = new(OnProgress);

        try
        {
            IReadOnlyList<CategoryScanResult> results =
                await _services.Scan.ScanAsync(_categories, reporter, _cts.Token);

            IsRunning = false;
            _main.GoTo(new ConfirmStepViewModel(_services, _main, _categories, results));
        }
        catch (OperationCanceledException)
        {
            IsRunning = false;
            _main.StartOver();
        }
    }

    private void OnProgress(ScanProgress progress)
    {
        CleanupCategory? category = _categories.FirstOrDefault(c => c.Id == progress.CategoryId);
        if (category is null)
        {
            return;
        }

        CategoryProgress row = Progress.First(p => p.DisplayName == category.DisplayName);
        row.Status = progress.CurrentPath.Length == 0
            ? $"{progress.ItemsFound} elementi · {FormatBytes(progress.BytesFound)}"
            : "in corso…";

        if (progress.CurrentPath.Length > 0)
        {
            CurrentPath = progress.CurrentPath;
        }
    }

    [RelayCommand]
    private void Cancel() => _cts.Cancel();
}
