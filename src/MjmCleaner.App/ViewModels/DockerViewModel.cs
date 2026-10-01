using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.App.ViewModels;

/// <summary>Una risorsa Docker nella schermata di conferma.</summary>
public sealed partial class DockerRow(DockerCandidate candidate, bool showCheckBox) : ObservableObject
{
    [ObservableProperty]
    private bool _isSelected = candidate.SelectedByDefault;

    public DockerCandidate Candidate { get; } = candidate;
    public bool ShowCheckBox { get; } = showCheckBox;
    public bool RequiresIndividualConfirmation { get; } = DockerConfirmationGroups.RequiresIndividualConfirmation(candidate);

    public string Name => Candidate.DisplayName;
    public string SizeText => Candidate.SizeBytes is { } bytes ? ViewModelBase.FormatBytes(bytes) : "—";

    public string KindLabel => Candidate.Kind switch
    {
        DockerResourceKind.Image => "immagine",
        DockerResourceKind.Volume => "volume",
        _ => "cache",
    };

    public string DetailText
    {
        get
        {
            string cost = Candidate.Cost.Length == 0 ? string.Empty : $" · costo: {Candidate.Cost}";
            string individual = RequiresIndividualConfirmation ? " · si conferma solo singolarmente" : string.Empty;
            return Candidate.Reason + cost + individual;
        }
    }
}

public sealed partial class DockerGroupNode : ObservableObject
{
    private bool _syncing;

    [ObservableProperty]
    private bool _isSelected;

    public DockerGroupNode(DockerConfirmationGroup definition)
    {
        Definition = definition;
        Rows = [.. definition.Items.Select(item => new DockerRow(item, definition.Mode == DockerGroupMode.Selectable))];
        _isSelected = definition.SelectedByDefault;

        foreach (DockerRow row in Rows)
        {
            row.PropertyChanged += OnRowChanged;
        }
    }

    public DockerConfirmationGroup Definition { get; }
    public ObservableCollection<DockerRow> Rows { get; }

    public string Title => Definition.Title;
    public string Description => Definition.Description;

    /// <summary>Le voci da tenere restano chiuse: si guardano solo se servono.</summary>
    public bool IsExpanded => Definition.Mode != DockerGroupMode.ReadOnly;

    /// <summary>
    /// La casella del gruppo esiste per i blocchi e per i gruppi in cui almeno una voce si può
    /// selezionare insieme alle altre: un gruppo di soli volumi con nome non ne ha bisogno.
    /// </summary>
    public bool ShowGroupCheckBox => Definition.Mode switch
    {
        DockerGroupMode.Block => true,
        DockerGroupMode.Selectable => Rows.Any(r => !r.RequiresIndividualConfirmation),
        _ => false,
    };

    public string GroupCheckBoxLabel => Definition.Mode == DockerGroupMode.Block ? "Elimina in blocco" : "Seleziona tutte";

    public string SummaryText =>
        $"{Rows.Count:N0} {ViewModelBase.Plural(Rows.Count, "voce", "voci")} · {ViewModelBase.FormatBytes(Rows.Sum(r => r.Candidate.SizeBytes ?? 0))}";

    partial void OnIsSelectedChanged(bool value)
    {
        if (_syncing || Definition.Mode != DockerGroupMode.Selectable)
        {
            return;
        }

        _syncing = true;
        foreach (DockerRow row in Rows.Where(r => !r.RequiresIndividualConfirmation))
        {
            row.IsSelected = value;
        }

        _syncing = false;
    }

    private void OnRowChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_syncing || e.PropertyName != nameof(DockerRow.IsSelected))
        {
            return;
        }

        _syncing = true;
        IsSelected = Rows.Where(r => !r.RequiresIndividualConfirmation).All(r => r.IsSelected);
        _syncing = false;
    }
}

/// <summary>
/// Pagina Docker: analisi in sola lettura, anteprima con selezione, esecuzione. L'anteprima è il
/// dry-run — nessun comando distruttivo parte prima di "Elimina".
/// </summary>
public sealed partial class DockerViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;
    private CancellationTokenSource? _deleteCts;
    private DockerDiskUsage? _diskBefore;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(RetryCommand))]
    private bool _isLoading = true;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasError))]
    private string _errorText = string.Empty;

    public bool HasError => ErrorText.Length > 0;

    /// <summary>
    /// Notifica il comando "Elimina": <see cref="CanDelete"/> dipende da questa proprietà, che
    /// diventa vera DOPO il primo ricalcolo della selezione — senza notifica il pulsante restava
    /// disabilitato con le voci sicure già selezionate.
    /// </summary>
    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(DeleteCommand))]
    private bool _isReady;

    [ObservableProperty]
    private string _serverText = string.Empty;

    [ObservableProperty]
    private string _diskText = string.Empty;

    [ObservableProperty]
    private string _dfText = string.Empty;

    [ObservableProperty]
    private string _totalText = string.Empty;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(DeleteCommand))]
    [NotifyCanExecuteChangedFor(nameof(CancelDeleteCommand))]
    private bool _isDeleting;

    [ObservableProperty]
    private string _deleteProgressText = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasDeleteError))]
    private string _deleteErrorText = string.Empty;

    public bool HasDeleteError => DeleteErrorText.Length > 0;

    public DockerViewModel(AppServices services, MainWindowViewModel main)
    {
        _services = services;
        _main = main;
        _ = LoadAsync();
    }

    public ObservableCollection<DockerGroupNode> Groups { get; } = [];

    private async Task LoadAsync()
    {
        IsLoading = true;
        IsReady = false;
        ErrorText = string.Empty;
        Groups.Clear();

        try
        {
            DockerAnalysis analysis = await _services.Docker.AnalyzeAsync(_services.ExpandedProjectRoots(), CancellationToken.None);

            _diskBefore = analysis.Disk;
            ServerText = $"Docker {analysis.ServerVersion} in esecuzione";
            DiskText = DescribeDisk(analysis.Disk);
            DfText = DescribeDf(analysis.Snapshot.Df);

            foreach (DockerConfirmationGroup group in DockerConfirmationGroups.Build(analysis.Candidates))
            {
                DockerGroupNode node = new(group);
                node.PropertyChanged += (_, _) => Recalculate();
                foreach (DockerRow row in node.Rows)
                {
                    row.PropertyChanged += (_, _) => Recalculate();
                }

                Groups.Add(node);
            }

            Recalculate();
            IsReady = true;
        }
        catch (DockerUnavailableException ex)
        {
            // Messaggio già pensato per l'utente: nessuno stack trace, e Docker Desktop non viene
            // avviato da qui — è l'utente a deciderlo.
            ErrorText = ex.Message;
        }
        catch (Exception ex)
        {
            ErrorText = $"Analisi di Docker non riuscita: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private bool CanRetry() => !IsLoading;

    [RelayCommand(CanExecute = nameof(CanRetry))]
    private Task RetryAsync() => LoadAsync();

    private IReadOnlyList<DockerCandidate> Selection()
        => DockerConfirmationGroups.Selection(
            [.. Groups.Select(g => g.Definition)],
            group => Groups.First(g => ReferenceEquals(g.Definition, group)).IsSelected,
            candidate => Groups.SelectMany(g => g.Rows).First(r => ReferenceEquals(r.Candidate, candidate)).IsSelected);

    private void Recalculate()
    {
        IReadOnlyList<DockerCandidate> selected = Selection();
        long bytes = selected.Sum(c => c.SizeBytes ?? 0);

        TotalText = $"{FormatBytes(bytes)} · {selected.Count:N0} {Plural(selected.Count, "voce", "voci")}";
        DeleteCommand.NotifyCanExecuteChanged();
    }

    private bool CanDelete() => IsReady && !IsDeleting && Selection().Count > 0;

    [RelayCommand(CanExecute = nameof(CanDelete))]
    private async Task DeleteAsync()
    {
        IsDeleting = true;
        DeleteErrorText = string.Empty;

        try
        {
            IReadOnlyList<DockerCandidate> selected = Selection();
            _deleteCts = new CancellationTokenSource();
            Progress<CleanProgress> reporter = new(p =>
                DeleteProgressText = $"{p.ItemsDone:N0} / {p.ItemsTotal:N0} · {p.CurrentPath}");

            DockerCleanResult result = await _services.Docker.ExecuteAsync(selected, reporter, _deleteCts.Token);
            DockerDiskUsage diskAfter = await _services.Docker.MeasureDiskAsync(CancellationToken.None);

            _main.GoTo(new DockerReportViewModel(_services, _main, result, _diskBefore, diskAfter));
        }
        catch (DockerUnavailableException ex)
        {
            DeleteErrorText = ex.Message;
        }
        catch (Exception ex)
        {
            DeleteErrorText = $"Pulizia non riuscita: {ex.Message}";
        }
        finally
        {
            IsDeleting = false;
        }
    }

    private bool CanCancelDelete() => IsDeleting;

    [RelayCommand(CanExecute = nameof(CanCancelDelete))]
    private void CancelDelete() => _deleteCts?.Cancel();

    [RelayCommand]
    private void Close() => _main.StartOver();

    internal static string DescribeDisk(DockerDiskUsage disk)
        => disk switch
        {
            { Exists: false } => "Disco virtuale di Docker Desktop non trovato: lo spazio occupato sul Mac non è misurabile.",
            { AllocatedBytes: { } allocated, ApparentBytes: { } apparent } =>
                $"Docker.raw occupa {FormatBytes(allocated)} sul disco (dimensione apparente {FormatBytes(apparent)}: è il limite massimo del disco virtuale, non lo spazio usato).",
            _ => "Docker.raw trovato, ma lo spazio occupato non è misurabile.",
        };

    internal static string DescribeDf(DockerDfSummary df)
        => string.Join(" · ", df.Entries
            .Where(e => e.Type != "Containers")
            .Select(e => $"{TypeLabel(e.Type)} {FormatBytes(e.SizeBytes)} (recuperabili {FormatBytes(e.ReclaimableBytes)})"));

    internal static string TypeLabel(string dfType) => dfType switch
    {
        DockerDfSummary.ImagesType => "Immagini",
        DockerDfSummary.VolumesType => "Volumi",
        DockerDfSummary.BuildCacheType => "Cache di build",
        _ => dfType,
    };
}
