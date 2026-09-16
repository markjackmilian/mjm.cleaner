using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.App.ViewModels;

/// <summary>
/// Una riga selezionabile: un singolo <see cref="ScanItem"/>, non la root della regola che lo ha
/// prodotto. Raggruppare per <c>ScanItem.DeclaredRoot</c> mostrerebbe una sola casella per
/// migliaia di elementi (la root delle regole a svuotamento — <c>~/Library/Caches</c>,
/// <c>$TMPDIR</c> — sopravvive comunque alla pulizia, quindi quella casella nominerebbe qualcosa
/// che non verrà mai cancellato) e renderebbe la granularità di deselezione qui identica a
/// quella già disponibile al passo 1, vanificando questo passo come rete di sicurezza.
/// </summary>
public sealed partial class PathNode(ScanItem item) : ObservableObject
{
    [ObservableProperty]
    private bool _isSelected = true;

    public string Path { get; } = item.Path;
    public ScanItem Item { get; } = item;
    public long SizeBytes { get; } = item.SizeBytes;
    public string SizeText => ViewModelBase.FormatBytes(SizeBytes);
}

public sealed class CategoryNode(string categoryId, string displayName, IEnumerable<PathNode> paths)
{
    public string CategoryId { get; } = categoryId;
    public string DisplayName { get; } = displayName;
    public ObservableCollection<PathNode> Paths { get; } = [.. paths];

    /// <summary>
    /// Prima la granularità per elemento mostrava questo totale implicitamente (una casella per
    /// root, con conteggio e dimensione). Ora che ogni riga è un elemento, un riepilogo per
    /// categoria mantiene visibile lo stesso totale a colpo d'occhio, prima di espandere.
    /// </summary>
    public string SummaryText =>
        $"{Paths.Count:N0} {ViewModelBase.Plural(Paths.Count, "elemento", "elementi")} · {ViewModelBase.FormatBytes(Paths.Sum(p => p.SizeBytes))}";
}

public sealed partial class ConfirmStepViewModel : ViewModelBase
{
    /// <summary>Oltre questo numero di nomi l'avviso diventa illeggibile proprio nel passo in cui l'utente deve decidere.</summary>
    private const int MaxRunningAppNamesShown = 5;

    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;

    private CancellationTokenSource? _deleteCts;

    [ObservableProperty]
    private string _totalText = string.Empty;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(DeleteCommand))]
    [NotifyCanExecuteChangedFor(nameof(CancelDeleteCommand))]
    private bool _isDeleting;

    /// <summary>Aggiornato dall'avanzamento reale del motore di pulizia durante l'eliminazione.</summary>
    [ObservableProperty]
    private string _deleteProgressText = string.Empty;

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

        // Un elemento, una riga: vedi il commento su PathNode per il perché.
        Nodes = [.. results
            .Where(r => r.Items.Count > 0)
            .Select(result => new CategoryNode(
                result.CategoryId,
                categories.First(c => c.Id == result.CategoryId).DisplayName,
                result.Items.Select(item => new PathNode(item))))];

        foreach (PathNode node in Nodes.SelectMany(n => n.Paths))
        {
            node.PropertyChanged += OnNodeChanged;
        }

        // Elenco di ciò che le protezioni hanno tolto d'ufficio: se un totale non torna,
        // qui se ne trova il motivo.
        GuardExclusion[] exclusions = [.. results.SelectMany(r => r.Exclusions)];
        ExclusionsText = exclusions.Length == 0
            ? string.Empty
            : $"{exclusions.Length} {Plural(exclusions.Length, "elemento escluso", "elementi esclusi")} dalle protezioni:\n" +
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
            string suffix = remaining switch
            {
                <= 0 => string.Empty,
                1 => " e un'altra",
                _ => $" e altre {remaining}",
            };

            string cacheClause = affected.Length == 1
                ? "la sua cache potrebbe rigenerarsi subito"
                : "le loro cache potrebbero rigenerarsi subito";

            RunningAppsWarning = $"{shown}{suffix} in esecuzione: {cacheClause}.";
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
        int items = selected.Length;

        TotalText = $"{FormatBytes(bytes)} · {items:N0} {Plural(items, "elemento", "elementi")}";
        DeleteCommand.NotifyCanExecuteChanged();
    }

    private bool CanDelete() => !IsDeleting && Nodes.SelectMany(n => n.Paths).Any(p => p.IsSelected);

    [RelayCommand(CanExecute = nameof(CanDelete))]
    private async Task DeleteAsync()
    {
        IsDeleting = true;

        CategorySelection[] selections =
        [
            .. Nodes
                .Select(node => new CategorySelection(
                    node.CategoryId,
                    [.. node.Paths.Where(p => p.IsSelected).Select(p => p.Item)]))
                .Where(s => s.Items.Count > 0),
        ];

        _deleteCts = new CancellationTokenSource();
        Progress<CleanProgress> reporter = new(OnDeleteProgress);

        // CleanAsync non solleva sull'annullamento: restituisce un resoconto parziale, che va
        // comunque al passo 4 e comunque nello storico — ciò che è già stato cancellato deve
        // risultare, annullamento o non annullamento.
        CleanReport report = await _services.Clean.CleanAsync(selections, reporter, _deleteCts.Token);

        _main.GoTo(new DoneStepViewModel(_services, _main, report));
    }

    private void OnDeleteProgress(CleanProgress progress)
    {
        DeleteProgressText =
            $"{progress.ItemsDone:N0} / {progress.ItemsTotal:N0} {Plural(progress.ItemsTotal, "elemento", "elementi")} · {FormatBytes(progress.BytesFreed)}";
    }

    private bool CanCancelDelete() => IsDeleting;

    [RelayCommand(CanExecute = nameof(CanCancelDelete))]
    private void CancelDelete() => _deleteCts?.Cancel();

    /// <summary>
    /// Deliberatamente non chiamato "Indietro": ricomincia dal passo 1 (la selezione resta
    /// ricordata nelle impostazioni) invece di tornare al passo 2 conservando questa analisi.
    /// Un'etichetta "← Indietro" prometterebbe di restare sul lavoro già fatto — cosa che questo
    /// comando non fa, e che tornare davvero al passo precedente richiederebbe di rieseguire la
    /// scansione o di farla sopravvivere alla navigazione: nessuna delle due è ciò che questo
    /// pulsante offre.
    /// </summary>
    [RelayCommand]
    private void Restart() => _main.StartOver();
}
