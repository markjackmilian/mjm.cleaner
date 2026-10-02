using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.Core.History;
using MjmCleaner.Core.Xcode;

namespace MjmCleaner.App.ViewModels;

public sealed class XcodeResultRow(XcodeItemResult item) : ObservableObject
{
    public XcodeItemResult Item { get; } = item;
    public string Name => Item.Candidate.Name;
    public string Identity => Item.Candidate.Path ?? Item.Candidate.CliId ?? Item.Candidate.Key;
    public string OutcomeText => Item.Outcome switch
    {
        XcodeItemOutcome.Deleted => "Eliminata",
        XcodeItemOutcome.Skipped => "Saltata",
        XcodeItemOutcome.Failed => "Non riuscita",
        _ => "Esito incerto",
    };
    public string SizeText => Item.VerifiedEstimatedBytes is { } bytes ? ViewModelBase.FormatBytes(bytes) : "non disponibile";
    public string Detail => Item.Reason;
}

public sealed partial class XcodeReportViewModel : ViewModelBase
{
    private readonly IHistoryStore _history;
    private readonly ISessionLogWriter _log;
    private readonly IXcodeNavigation _navigation;
    private readonly IXcodeCleanupService _xcode;
    private readonly XcodeCleanResult _result;
    private Task? _persistenceTask;

    [ObservableProperty] private string _historyWarning = string.Empty;
    public ObservableCollection<XcodeResultRow> Items { get; }
    public string FreedText { get; }
    public string SummaryText { get; }
    public string FreeSpaceText { get; }
    public string WarningsText { get; }
    public bool HasWarnings => WarningsText.Length > 0;
    public bool HasHistoryWarning => HistoryWarning.Length > 0;
    public Task PersistenceTask => _persistenceTask ??= PersistOnceAsync();

    partial void OnHistoryWarningChanged(string value) => OnPropertyChanged(nameof(HasHistoryWarning));

    public XcodeReportViewModel(IXcodeCleanupService xcode, IHistoryStore history, ISessionLogWriter log, IXcodeNavigation navigation, XcodeCleanResult result)
    {
        _xcode = xcode; _history = history; _log = log; _navigation = navigation; _result = result;
        Items = [.. result.Items.Select(i => new XcodeResultRow(i))];
        FreedText = $"{result.HistoryReport.BytesFreed:N0} byte stimati conteggiati nella cronologia";
        SummaryText = $"{result.HistoryReport.ItemsDeleted:N0} eliminate · {result.Items.Count(i => i.Outcome == XcodeItemOutcome.Skipped):N0} saltate · {result.Items.Count(i => i.Outcome == XcodeItemOutcome.Failed):N0} non riuscite · {result.Items.Count(i => i.Outcome == XcodeItemOutcome.Uncertain):N0} incerte";
        FreeSpaceText = (result.FreeBytesBefore, result.FreeBytesAfter) switch
        {
            ({ } before, { } after) when after >= before => $"Spazio libero rilevato: +{ViewModelBase.FormatBytes(after - before)} ({ViewModelBase.FormatBytes(before)} → {ViewModelBase.FormatBytes(after)}). Variazione separata dalle stime eliminate.",
            ({ } before, { } after) => $"Spazio libero rilevato: {ViewModelBase.FormatBytes(before)} → {ViewModelBase.FormatBytes(after)}. La variazione può dipendere da altre attività.",
            _ => "Spazio libero prima o dopo: non disponibile.",
        };
        WarningsText = string.Join("\n", result.Warnings);
        _persistenceTask = PersistOnceAsync();
    }

    private async Task PersistOnceAsync()
    {
        bool historySaved = false;
        bool logSaved = false;
        try
        {
            long id = await _history.SaveAsync(_result.HistoryReport, CancellationToken.None);
            historySaved = true;
            await _log.WriteAsync(id, _result.HistoryReport, CancellationToken.None);
            logSaved = true;
            await _navigation.RefreshTotalAsync();
        }
        catch (Exception ex)
        {
            HistoryWarning = historySaved
                ? logSaved ? "Cronologia e log salvati, ma il contatore cumulativo non è stato aggiornato: " + ex.Message
                    : "Cronologia salvata, ma il log di sessione non è stato aggiornato: " + ex.Message
                : "Pulizia completata, ma il report non è stato salvato nello storico: " + ex.Message;
        }
    }

    [RelayCommand]
    private Task Persist() => PersistenceTask;

    [RelayCommand]
    private void AnalyzeAgain() => _navigation.GoTo(new XcodeViewModel(_xcode, _history, _log, _navigation));

    [RelayCommand]
    private void Close() => _navigation.StartOver();

}
