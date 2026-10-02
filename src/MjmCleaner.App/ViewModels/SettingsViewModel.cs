using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App.ViewModels;

public sealed partial class SettingsViewModel : ViewModelBase
{
    private readonly ISettingsStore _store;
    private readonly IAppearanceController _appearance;
    private readonly IFolderPicker _folders;
    private readonly Action _onSaved;
    private readonly AppearancePreference _loadedAppearance;
    private bool _saved;

    /// <summary>
    /// Byte esatti letti al caricamento, insieme al valore in MB troncato che ne deriva.
    /// Se al salvataggio il campo mostrato non è cambiato, si riscrivono questi byte
    /// invariati invece di ricalcolarli da MB: altrimenti un valore che non è multiplo
    /// esatto di un megabyte perderebbe precisione a ogni salvataggio, anche quando
    /// l'utente modifica un campo del tutto scorrelato.
    /// </summary>
    private readonly long _loadedThresholdBytes;
    private readonly int _loadedThresholdMegabytes;

    // La proprietà generata «AppearancePreference» ha lo stesso nome del tipo enum;
    // «Appearance» è l'alias di sola lettura per chi legge la scelta corrente.
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Appearance), nameof(IsAuto), nameof(IsLight), nameof(IsDark))]
    private AppearancePreference _appearancePreference;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(RemoveProjectRootCommand))]
    private string? _selectedProjectRoot;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(RemoveLargeFileRootCommand))]
    private string? _selectedLargeFileRoot;

    [ObservableProperty] private int _largeFileThresholdMegabytes;
    [ObservableProperty] private int _downloadsMinAgeDays;
    [ObservableProperty] private int _logsMinAgeDays;
    [ObservableProperty] private int _nuGetMinAgeDays;

    public SettingsViewModel(ISettingsStore store, IAppearanceController appearance, IFolderPicker folders, Action onSaved)
    {
        _store = store;
        _appearance = appearance;
        _folders = folders;
        _onSaved = onSaved;

        CleanerSettings settings = store.Load();
        _loadedAppearance = settings.Appearance;
        _appearancePreference = settings.Appearance;
        ProjectRoots = [.. settings.ProjectRoots];
        LargeFileRoots = [.. settings.LargeFileRoots];
        _loadedThresholdBytes = settings.LargeFileThresholdBytes;
        _loadedThresholdMegabytes = (int)(settings.LargeFileThresholdBytes / (1024 * 1024));
        _largeFileThresholdMegabytes = _loadedThresholdMegabytes;
        _downloadsMinAgeDays = settings.DownloadsMinAgeDays;
        _logsMinAgeDays = settings.LogsMinAgeDays;
        _nuGetMinAgeDays = settings.NuGetMinAgeDays;
    }

    /// <summary>Richiesta di chiusura della finestra (dopo Salva o Annulla).</summary>
    public event EventHandler? CloseRequested;

    public ObservableCollection<string> ProjectRoots { get; }
    public ObservableCollection<string> LargeFileRoots { get; }

    public AppearancePreference Appearance => AppearancePreference;

    public bool IsAuto { get => AppearancePreference == AppearancePreference.Auto; set { if (value) AppearancePreference = AppearancePreference.Auto; } }
    public bool IsLight { get => AppearancePreference == AppearancePreference.Light; set { if (value) AppearancePreference = AppearancePreference.Light; } }
    public bool IsDark { get => AppearancePreference == AppearancePreference.Dark; set { if (value) AppearancePreference = AppearancePreference.Dark; } }

    /// <summary>L'aspetto scelto si vede subito: diventa definitivo solo con Salva.</summary>
    partial void OnAppearancePreferenceChanged(AppearancePreference value) => _appearance.Apply(value);

    [RelayCommand]
    private void Save()
    {
        long thresholdBytes = LargeFileThresholdMegabytes == _loadedThresholdMegabytes
            ? _loadedThresholdBytes
            : Math.Max(1, LargeFileThresholdMegabytes) * 1024L * 1024L;

        CleanerSettings settings = _store.Load() with
        {
            Appearance = AppearancePreference,
            ProjectRoots = [.. ProjectRoots],
            LargeFileRoots = [.. LargeFileRoots],
            LargeFileThresholdBytes = thresholdBytes,
            DownloadsMinAgeDays = Math.Max(0, DownloadsMinAgeDays),
            LogsMinAgeDays = Math.Max(0, LogsMinAgeDays),
            NuGetMinAgeDays = Math.Max(0, NuGetMinAgeDays),
        };

        _store.Save(settings);
        _saved = true;
        _onSaved();
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    [RelayCommand]
    private void Cancel()
    {
        Dismiss();
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>Chiusura senza salvare (Annulla o pulsante rosso): torna l'aspetto di prima. Idempotente.</summary>
    public void Dismiss()
    {
        if (!_saved) _appearance.Apply(_loadedAppearance);
    }

    [RelayCommand]
    private async Task AddProjectRootAsync()
        => SelectedProjectRoot = await AddFolderAsync(ProjectRoots, "Scegli una cartella di progetto") ?? SelectedProjectRoot;

    [RelayCommand(CanExecute = nameof(CanRemoveProjectRoot))]
    private void RemoveProjectRoot()
    {
        if (SelectedProjectRoot is { } root) ProjectRoots.Remove(root);
        SelectedProjectRoot = null;
    }

    private bool CanRemoveProjectRoot() => SelectedProjectRoot is not null;

    [RelayCommand]
    private async Task AddLargeFileRootAsync()
        => SelectedLargeFileRoot = await AddFolderAsync(LargeFileRoots, "Scegli una cartella in cui cercare file grandi") ?? SelectedLargeFileRoot;

    [RelayCommand(CanExecute = nameof(CanRemoveLargeFileRoot))]
    private void RemoveLargeFileRoot()
    {
        if (SelectedLargeFileRoot is { } root) LargeFileRoots.Remove(root);
        SelectedLargeFileRoot = null;
    }

    private bool CanRemoveLargeFileRoot() => SelectedLargeFileRoot is not null;

    private async Task<string?> AddFolderAsync(ObservableCollection<string> target, string title)
    {
        string? path = await _folders.PickFolderAsync(title);
        if (path is null) return null;
        if (!target.Contains(path, StringComparer.Ordinal)) target.Add(path);
        return path;
    }
}
