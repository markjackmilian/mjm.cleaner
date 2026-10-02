using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.History;
using MjmCleaner.Core.Xcode;

namespace MjmCleaner.App.ViewModels;

public interface IXcodeNavigation
{
    void GoTo(object page);
    void StartOver();
    Task RefreshTotalAsync();
}

public sealed partial class XcodeRow(XcodeCandidate candidate) : ObservableObject
{
    [ObservableProperty] private bool _isSelected;
    public XcodeCandidate Candidate { get; } = candidate;
    public string Name => Candidate.Name;
    public string SizeText => Candidate.SizeBytes is { } size ? ViewModelBase.FormatBytes(size) : "non disponibile";
    public string IdentityText => Candidate.Path ?? Candidate.CliId ?? Candidate.Key;
    public string StateText => Candidate.BlockReason ?? Candidate.State ?? string.Empty;
    public bool HasState => StateText.Length > 0;
    public bool CanSelect => Candidate.CanSelect;
}

public sealed partial class XcodeGroupNode : ObservableObject
{
    private bool _sync;
    [ObservableProperty] private bool _isSelected;
    public XcodeGroupNode(XcodeResourceKind kind, IEnumerable<XcodeCandidate> candidates, IReadOnlyList<string> warnings)
    {
        Kind = kind;
        Rows = [.. candidates.Select(c => new XcodeRow(c))];
        Warnings = warnings;
        foreach (XcodeRow row in Rows) row.PropertyChanged += OnRowChanged;
    }
    public XcodeResourceKind Kind { get; }
    public ObservableCollection<XcodeRow> Rows { get; }
    public IReadOnlyList<string> Warnings { get; }
    public string Title => Kind switch
    {
        XcodeResourceKind.DerivedData => "DerivedData",
        XcodeResourceKind.DeviceSupport => "Device Support",
        XcodeResourceKind.Device => "Dispositivi simulati",
        _ => "Runtime iOS, watchOS, tvOS e visionOS",
    };
    public bool IsExpanded => Kind is XcodeResourceKind.DerivedData or XcodeResourceKind.DeviceSupport;
    public bool ShowGroupCheckBox => Kind is XcodeResourceKind.DerivedData or XcodeResourceKind.DeviceSupport;
    public string Summary
    {
        get
        {
            bool hasKnownSizes = Rows.Any(r => r.Candidate.SizeBytes.HasValue);
            long knownBytes = Rows.Where(r => r.Candidate.SizeBytes.HasValue).Sum(r => r.Candidate.SizeBytes!.Value);
            int unknownCount = Rows.Count(r => r.Candidate.SizeBytes is null);
            string size = hasKnownSizes ? $"{ViewModelBase.FormatBytes(knownBytes)} stimati noti" : "dimensioni non disponibili";
            if (hasKnownSizes && unknownCount > 0)
            {
                string unknownLabel = unknownCount == 1 ? "1 dimensione non disponibile" : $"{unknownCount} dimensioni non disponibili";
                size += $" · {unknownLabel}";
            }
            return $"{Rows.Count:N0} voci · {size}";
        }
    }
    partial void OnIsSelectedChanged(bool value)
    {
        if (_sync || !ShowGroupCheckBox) return;
        _sync = true;
        foreach (XcodeRow row in Rows.Where(r => r.CanSelect)) row.IsSelected = value;
        _sync = false;
    }
    private void OnRowChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_sync || e.PropertyName != nameof(XcodeRow.IsSelected) || !ShowGroupCheckBox) return;
        _sync = true;
        IsSelected = Rows.Where(r => r.CanSelect).Any() && Rows.Where(r => r.CanSelect).All(r => r.IsSelected);
        _sync = false;
    }
}

public sealed partial class XcodeViewModel : ViewModelBase
{
    private readonly IXcodeCleanupService _xcode;
    private readonly IHistoryStore _history;
    private readonly ISessionLogWriter _log;
    private readonly IXcodeNavigation _navigation;
    private CancellationTokenSource? _deleteCts;
    private XcodeSnapshot? _snapshot;
    private bool _executionStarted;

    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(RetryCommand))] private bool _isLoading = true;
    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(RetryCommand))] [NotifyCanExecuteChangedFor(nameof(CloseCommand))] [NotifyCanExecuteChangedFor(nameof(BackToSelectionCommand))] [NotifyCanExecuteChangedFor(nameof(PreviewCommand))] private bool _isDeleting;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(HasError))] private string _errorText = string.Empty;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(HasWarnings))] private string _warningText = string.Empty;
    [ObservableProperty] private string _totalText = string.Empty;
    [ObservableProperty] private string _progressText = string.Empty;
    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(ConfirmDeleteCommand))] private bool _acknowledgeDependencies;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(HasConfirmation))] [NotifyPropertyChangedFor(nameof(PreviewSummaryText))] [NotifyPropertyChangedFor(nameof(PreviewEstimateText))] [NotifyPropertyChangedFor(nameof(HasRetainedDependencies))] [NotifyPropertyChangedFor(nameof(HasSelectedDevices))] [NotifyPropertyChangedFor(nameof(HasSelectedRuntimes))] [NotifyCanExecuteChangedFor(nameof(ConfirmDeleteCommand))] private XcodeConfirmation? _confirmation;
    [ObservableProperty] private XcodeReportViewModel? _currentReport;
    public bool HasError => ErrorText.Length > 0;
    public bool HasWarnings => WarningText.Length > 0;
    public bool HasConfirmation => Confirmation is not null;
    public bool HasRetainedDependencies => Confirmation?.RetainedDependentDevices.Count > 0;
    public bool HasSelectedDevices => Confirmation?.SelectedCandidates.Any(c => c.Kind == XcodeResourceKind.Device) == true;
    public bool HasSelectedRuntimes => Confirmation?.SelectedCandidates.Any(c => c.Kind == XcodeResourceKind.Runtime) == true;
    public string PreviewSummaryText => Confirmation is null ? string.Empty : $"Risorse selezionate: {Confirmation.SelectedCandidates.Count}";
    public string PreviewEstimateText => Confirmation is null ? string.Empty
        : $"Stima nota: {FormatBytes(Confirmation.EstimatedBytes)}" + (Confirmation.UnknownSizeCount > 0 ? $" · {Confirmation.UnknownSizeCount} dimensioni non disponibili" : string.Empty);
    public Task InitialLoad { get; }
    public ObservableCollection<XcodeGroupNode> Groups { get; } = [];

    public XcodeViewModel(IXcodeCleanupService xcode, IHistoryStore history, ISessionLogWriter log, IXcodeNavigation navigation)
    {
        _xcode = xcode; _history = history; _log = log; _navigation = navigation;
        InitialLoad = LoadAsync();
    }

    private async Task LoadAsync()
    {
        IsLoading = true; ErrorText = string.Empty; WarningText = string.Empty; Confirmation = null; AcknowledgeDependencies = false; Groups.Clear(); _snapshot = null;
        if (!IsDeleting)
        {
            _executionStarted = false;
            ConfirmDeleteCommand.NotifyCanExecuteChanged();
        }
        try
        {
            XcodeSnapshot snapshot = await _xcode.AnalyzeAsync(CancellationToken.None);
            _snapshot = snapshot;
            foreach (XcodeResourceKind kind in Enum.GetValues<XcodeResourceKind>())
            {
                XcodeGroupNode group = new(kind, snapshot.Candidates.Where(c => c.Kind == kind), snapshot.Warnings.Where(w => w.ResourceGroup == kind).Select(w => w.Message).ToArray());
                foreach (XcodeRow row in group.Rows) row.PropertyChanged += OnSelectionChanged;
                group.PropertyChanged += OnSelectionChanged;
                Groups.Add(group);
            }
            WarningText = string.Join("\n", snapshot.Warnings.Select(w => w.Message).Distinct());
            Recalculate();
        }
        catch (Exception ex) { ErrorText = $"Analisi Xcode non riuscita: {ex.Message}"; }
        finally { IsLoading = false; }
    }

    private bool CanRetry() => !IsLoading && !IsDeleting;
    [RelayCommand(CanExecute = nameof(CanRetry))] private Task RetryAsync() => LoadAsync();
    private void OnSelectionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(XcodeRow.IsSelected) or nameof(XcodeGroupNode.IsSelected)) { Confirmation = null; AcknowledgeDependencies = false; Recalculate(); }
    }
    private HashSet<string> SelectedKeys() => Groups.SelectMany(g => g.Rows).Where(r => r.IsSelected && r.CanSelect).Select(r => r.Candidate.Key).ToHashSet(StringComparer.Ordinal);
    private void Recalculate()
    {
        long known = Groups.SelectMany(g => g.Rows).Where(r => r.IsSelected && r.CanSelect && r.Candidate.SizeBytes.HasValue).Sum(r => r.Candidate.SizeBytes!.Value);
        int unknown = Groups.SelectMany(g => g.Rows).Count(r => r.IsSelected && r.CanSelect && r.Candidate.SizeBytes is null);
        TotalText = $"{FormatBytes(known)} stimati · {SelectedKeys().Count} selezionate" + (unknown > 0 ? $" · {unknown} non disponibili" : string.Empty);
        PreviewCommand.NotifyCanExecuteChanged();
    }
    private bool CanPreview() => !IsDeleting && SelectedKeys().Count > 0;
    [RelayCommand(CanExecute = nameof(CanPreview))]
    private void Preview()
    {
        if (_snapshot is null || IsDeleting) return;
        try { Confirmation = XcodeSelection.Preview(_snapshot, SelectedKeys()); AcknowledgeDependencies = false; }
        catch (Exception ex) { ErrorText = ex.Message; }
    }
    private bool CanConfirmDelete() => !IsDeleting && !_executionStarted && Confirmation is { SelectedCandidates.Count: > 0 } c && (c.RetainedDependentDevices.Count == 0 || AcknowledgeDependencies);
    [RelayCommand(CanExecute = nameof(CanConfirmDelete))]
    private async Task ConfirmDeleteAsync()
    {
        if (_executionStarted || Confirmation is null) return;
        _executionStarted = true; ConfirmDeleteCommand.NotifyCanExecuteChanged(); IsDeleting = true; ErrorText = string.Empty;
        bool executionReturnedReport = false;
        try
        {
            XcodeConfirmedPlan plan = XcodeSelection.Confirm(Confirmation, AcknowledgeDependencies);
            _deleteCts = new CancellationTokenSource();
            IProgress<CleanProgress> progress = new Progress<CleanProgress>(p => ProgressText = $"{p.ItemsDone:N0} / {p.ItemsTotal:N0} · {p.CurrentPath}");
            XcodeCleanResult result = await _xcode.ExecuteAsync(plan, progress, _deleteCts.Token);
            executionReturnedReport = true;
            CurrentReport = new XcodeReportViewModel(_xcode, _history, _log, _navigation, result);
            _navigation.GoTo(CurrentReport);
        }
        catch (OperationCanceledException)
        {
            ErrorText = "Operazione interrotta prima di poter produrre il report.";
        }
        catch (Exception ex) { ErrorText = $"Pulizia Xcode non riuscita: {ex.Message}"; }
        finally
        {
            _deleteCts?.Dispose();
            _deleteCts = null;
            _executionStarted = executionReturnedReport;
            IsDeleting = false;
            ConfirmDeleteCommand.NotifyCanExecuteChanged();
        }
    }
    [RelayCommand(CanExecute = nameof(IsDeleting))] private void CancelDelete() => _deleteCts?.Cancel();
    private bool CanNavigate() => !IsDeleting;
    [RelayCommand(CanExecute = nameof(CanNavigate))] private void BackToSelection() { if (IsDeleting) return; Confirmation = null; AcknowledgeDependencies = false; }
    [RelayCommand(CanExecute = nameof(CanNavigate))] private void Close() { if (!IsDeleting) _navigation.StartOver(); }
}
