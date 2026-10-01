using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.App.ViewModels;

public sealed partial class DockerReportViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;
    private readonly CleanReport _report;

    [ObservableProperty]
    private string _historyWarning = string.Empty;

    public DockerReportViewModel(
        AppServices services,
        MainWindowViewModel main,
        DockerCleanResult result,
        DockerDiskUsage? diskBefore,
        DockerDiskUsage diskAfter)
    {
        _services = services;
        _main = main;
        _report = result.Report;

        FreedText = $"{FormatBytes(_report.BytesFreed)} recuperati";
        SummaryText = $"{_report.ItemsDeleted:N0} {Plural(_report.ItemsDeleted, "voce eliminata", "voci eliminate")}" +
                      (_report.ItemsFailed == 0 ? string.Empty : $" · {_report.ItemsFailed:N0} non {Plural(_report.ItemsFailed, "eliminata", "eliminate")}");

        DfText = result.After is null
            ? "docker system df: misura finale non disponibile."
            : $"docker system df: {FormatBytes(result.Before.Total)} → {FormatBytes(result.After.Total)}";

        DiskText = (diskBefore?.AllocatedBytes, diskAfter.AllocatedBytes) switch
        {
            ({ } before, { } after) => $"Docker.raw sul disco: {FormatBytes(before)} → {FormatBytes(after)}",
            _ => "Docker.raw sul disco: non misurabile.",
        };

        // Docker Desktop restituisce lo spazio al Mac in modo differito: il disco virtuale può
        // restare grande anche dopo una pulizia riuscita. Purge è l'unico modo per forzarlo, e
        // cancella TUTTO: lo si suggerisce, mai lo si esegue.
        PurgeHint = _report.ItemsDeleted > 0
                    && diskBefore?.AllocatedBytes is { } rawBefore
                    && diskAfter.AllocatedBytes is { } rawAfter
                    && rawAfter >= rawBefore
            ? "Docker.raw non si è ridotto: Docker Desktop restituisce lo spazio al Mac con calma. " +
              "Per recuperarlo subito: Docker Desktop → Troubleshoot → Clean / Purge data. " +
              "Attenzione: quell'operazione cancella tutte le immagini, i container e i volumi."
            : string.Empty;

        DaemonLostText = result.DaemonLost
            ? "Docker si è fermato durante la pulizia: le voci restanti non sono state eliminate."
            : string.Empty;

        Deleted = [.. _report.DeletedPaths.Select(Describe)];
        Failed = [.. _report.Errors.Select(e => $"{e.Path} — {e.Message}")];

        _ = PersistAsync();
    }

    public string FreedText { get; }
    public string SummaryText { get; }
    public string DfText { get; }
    public string DiskText { get; }
    public string PurgeHint { get; }
    public string DaemonLostText { get; }
    public ObservableCollection<string> Deleted { get; }
    public ObservableCollection<string> Failed { get; }
    public bool HasFailures => Failed.Count > 0;

    /// <summary>Come per il wizard: la pulizia è avvenuta anche se lo storico non si aggiorna, e va detto.</summary>
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

    /// <summary>"docker:image:sha256:… (nome)" → "immagine nome": l'identificativo completo resta nel log di sessione.</summary>
    private static string Describe(string logEntry)
    {
        const string Image = "docker:image:";
        const string Volume = "docker:volume:";

        if (logEntry.StartsWith(Image, StringComparison.Ordinal))
        {
            int open = logEntry.IndexOf(" (", StringComparison.Ordinal);
            return open > 0 ? $"immagine {logEntry[(open + 2)..^1]}" : $"immagine {logEntry[Image.Length..]}";
        }

        return logEntry.StartsWith(Volume, StringComparison.Ordinal)
            ? $"volume {logEntry[Volume.Length..]}"
            : "cache di build";
    }

    [RelayCommand]
    private void AnalyzeAgain() => _main.GoTo(new DockerViewModel(_services, _main));

    [RelayCommand]
    private void Close() => _main.StartOver();
}
