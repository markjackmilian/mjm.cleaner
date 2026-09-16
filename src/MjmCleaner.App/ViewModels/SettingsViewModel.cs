using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App.ViewModels;

public sealed partial class SettingsViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;

    [ObservableProperty] private string _projectRoots;
    [ObservableProperty] private string _largeFileRoots;
    [ObservableProperty] private int _largeFileThresholdMegabytes;
    [ObservableProperty] private int _downloadsMinAgeDays;
    [ObservableProperty] private int _logsMinAgeDays;
    [ObservableProperty] private int _nuGetMinAgeDays;

    public SettingsViewModel(AppServices services, MainWindowViewModel main)
    {
        _services = services;
        _main = main;

        CleanerSettings settings = services.Settings.Load();
        _projectRoots = string.Join(Environment.NewLine, settings.ProjectRoots);
        _largeFileRoots = string.Join(Environment.NewLine, settings.LargeFileRoots);
        _largeFileThresholdMegabytes = (int)(settings.LargeFileThresholdBytes / (1024 * 1024));
        _downloadsMinAgeDays = settings.DownloadsMinAgeDays;
        _logsMinAgeDays = settings.LogsMinAgeDays;
        _nuGetMinAgeDays = settings.NuGetMinAgeDays;
    }

    [RelayCommand]
    private void Save()
    {
        CleanerSettings settings = _services.Settings.Load() with
        {
            ProjectRoots = SplitLines(ProjectRoots),
            LargeFileRoots = SplitLines(LargeFileRoots),
            LargeFileThresholdBytes = Math.Max(1, LargeFileThresholdMegabytes) * 1024L * 1024L,
            DownloadsMinAgeDays = Math.Max(0, DownloadsMinAgeDays),
            LogsMinAgeDays = Math.Max(0, LogsMinAgeDays),
            NuGetMinAgeDays = Math.Max(0, NuGetMinAgeDays),
        };

        _services.Settings.Save(settings);
        _main.StartOver();
    }

    [RelayCommand]
    private void Cancel() => _main.StartOver();

    private static string[] SplitLines(string text)
        => [.. text
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)];
}
