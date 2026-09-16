using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.App.ViewModels;

public sealed partial class PathNode(string path, IReadOnlyList<ScanItem> items) : ObservableObject
{
    [ObservableProperty]
    private bool _isSelected = true;

    public string Path { get; } = path;
    public IReadOnlyList<ScanItem> Items { get; } = items;
    public long SizeBytes { get; } = items.Sum(i => i.SizeBytes);
    public string SizeText => ViewModelBase.FormatBytes(SizeBytes);
    public string CountText => $"{Items.Count} elementi";
}

public sealed class CategoryNode(string categoryId, string displayName, IEnumerable<PathNode> paths)
{
    public string CategoryId { get; } = categoryId;
    public string DisplayName { get; } = displayName;
    public ObservableCollection<PathNode> Paths { get; } = [.. paths];
}

public sealed partial class ConfirmStepViewModel : ViewModelBase
{
    /// <summary>Oltre questo numero di nomi l'avviso diventa illeggibile proprio nel passo in cui l'utente deve decidere.</summary>
    private const int MaxRunningAppNamesShown = 5;

    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;

    [ObservableProperty]
    private string _totalText = string.Empty;

    [ObservableProperty]
    private bool _isDeleting;

    /// <summary>
    /// Vuoto finché la sonda non ha risposto: viene popolato in modo asincrono, fuori dal thread
    /// dell'interfaccia, perché avvia un processo esterno (<c>ps</c>) che in uno scenario
    /// patologico può impiegare fino a una decina di secondi. La schermata resta utilizzabile nel
    /// frattempo.
    /// </summary>
    [ObservableProperty]
    private string _runningAppsWarning = string.Empty;

    public ConfirmStepViewModel(
        AppServices services,
        MainWindowViewModel main,
        IReadOnlyList<CleanupCategory> categories,
        IReadOnlyList<CategoryScanResult> results)
    {
        _services = services;
        _main = main;

        Nodes = [.. results
            .Where(r => r.Items.Count > 0)
            .Select(result => new CategoryNode(
                result.CategoryId,
                categories.First(c => c.Id == result.CategoryId).DisplayName,
                result.Items
                    .GroupBy(i => i.DeclaredRoot, StringComparer.Ordinal)
                    .Select(group => new PathNode(group.Key, [.. group]))))];

        foreach (PathNode node in Nodes.SelectMany(n => n.Paths))
        {
            node.PropertyChanged += OnNodeChanged;
        }

        // Elenco di ciò che le protezioni hanno tolto d'ufficio: se un totale non torna,
        // qui se ne trova il motivo.
        GuardExclusion[] exclusions = [.. results.SelectMany(r => r.Exclusions)];
        ExclusionsText = exclusions.Length == 0
            ? string.Empty
            : $"{exclusions.Length} elementi esclusi dalle protezioni:\n" +
              string.Join('\n', exclusions.Take(5).Select(e => $"· {e.Path} — {e.Reason}"));

        Recalculate();

        string[] scannedPaths = [.. results.SelectMany(r => r.Items).Take(2000).Select(i => i.Path)];
        _ = ComputeRunningAppsWarningAsync(scannedPaths);
    }

    public ObservableCollection<CategoryNode> Nodes { get; }
    public string ExclusionsText { get; }

    /// <summary>
    /// Interroga la sonda su un thread di background e formatta l'avviso al termine. Un
    /// fallimento nel calcolo non deve mai impedire la pulizia: l'avviso resta semplicemente vuoto.
    /// </summary>
    private async Task ComputeRunningAppsWarningAsync(IReadOnlyList<string> scannedPaths)
    {
        try
        {
            string[] affected = await Task.Run(() => _services.RunningApps.AffectedApps(scannedPaths).ToArray());

            if (affected.Length == 0)
            {
                RunningAppsWarning = string.Empty;
                return;
            }

            string shown = string.Join(", ", affected.Take(MaxRunningAppNamesShown));
            int remaining = affected.Length - MaxRunningAppNamesShown;
            string suffix = remaining > 0 ? $" e altre {remaining}" : string.Empty;

            RunningAppsWarning = $"{shown}{suffix} in esecuzione: le loro cache potrebbero rigenerarsi subito.";
        }
        catch (Exception)
        {
            RunningAppsWarning = string.Empty;
        }
    }

    private void OnNodeChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(PathNode.IsSelected))
        {
            Recalculate();
        }
    }

    private void Recalculate()
    {
        PathNode[] selected = [.. Nodes.SelectMany(n => n.Paths).Where(p => p.IsSelected)];
        long bytes = selected.Sum(p => p.SizeBytes);
        int items = selected.Sum(p => p.Items.Count);

        TotalText = $"{FormatBytes(bytes)} · {items:N0} elementi";
        DeleteCommand.NotifyCanExecuteChanged();
    }

    private bool CanDelete() => !IsDeleting && Nodes.SelectMany(n => n.Paths).Any(p => p.IsSelected);

    [RelayCommand(CanExecute = nameof(CanDelete))]
    private async Task DeleteAsync()
    {
        IsDeleting = true;
        DeleteCommand.NotifyCanExecuteChanged();

        CategorySelection[] selections =
        [
            .. Nodes
                .Select(node => new CategorySelection(
                    node.CategoryId,
                    [.. node.Paths.Where(p => p.IsSelected).SelectMany(p => p.Items)]))
                .Where(s => s.Items.Count > 0),
        ];

        CleanReport report = await _services.Clean.CleanAsync(selections, null, CancellationToken.None);

        _main.GoTo(new DoneStepViewModel(_services, _main, report));
    }

    [RelayCommand]
    private void Back() => _main.StartOver();
}
