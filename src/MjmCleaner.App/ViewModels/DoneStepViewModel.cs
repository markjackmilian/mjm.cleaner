using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.App.ViewModels;

public sealed partial class DoneStepViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;
    private readonly CleanReport _report;

    [ObservableProperty]
    private string _historyWarning = string.Empty;

    public DoneStepViewModel(AppServices services, MainWindowViewModel main, CleanReport report)
    {
        _services = services;
        _main = main;
        _report = report;

        FreedText = $"{FormatBytes(report.BytesFreed)} liberati";
        SummaryText = $"in {report.Duration.TotalSeconds:0} secondi · {report.ItemsDeleted:N0} elementi eliminati";

        Rows = [.. report.Categories
            .Where(c => c.ItemsDeleted > 0)
            .Select(c => $"{c.CategoryId} — {FormatBytes(c.BytesFreed)}")];

        ErrorsText = report.ItemsFailed == 0
            ? string.Empty
            : $"{report.ItemsFailed} elementi non eliminati. {DescribeErrors(report.Errors)}";

        _ = PersistAsync();
    }

    public string FreedText { get; }
    public string SummaryText { get; }
    public string ErrorsText { get; }
    public ObservableCollection<string> Rows { get; }

    /// <summary>
    /// Se la scrittura dello storico fallisce la pulizia è comunque avvenuta:
    /// va detto, senza far credere che non abbia cancellato nulla.
    /// </summary>
    private async Task PersistAsync()
    {
        try
        {
            long sessionId = await _services.History.SaveAsync(_report, CancellationToken.None);
            await _services.SessionLog.WriteAsync(sessionId, _report, CancellationToken.None);
            await _main.RefreshTotalAsync();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or Microsoft.Data.Sqlite.SqliteException)
        {
            HistoryWarning = "Pulizia completata, storico non aggiornato: " + ex.Message;
        }
    }

    private static string DescribeErrors(IReadOnlyList<ScanError> errors)
    {
        if (errors.Any(e => e.Kind == ScanErrorKind.AccessDenied))
        {
            return "Alcuni richiedono l'Accesso completo al disco: " +
                   "Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco.";
        }

        return errors.Any(e => e.Kind == ScanErrorKind.InUse)
            ? "Alcuni erano in uso da applicazioni aperte."
            : "Dettagli nel log della sessione.";
    }

    [RelayCommand]
    private void NewCleanup() => _main.StartOver();
}
