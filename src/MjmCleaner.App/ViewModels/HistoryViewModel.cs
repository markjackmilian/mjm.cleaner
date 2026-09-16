using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.History;

namespace MjmCleaner.App.ViewModels;

public sealed class HistoryRow(CleanSessionSummary session)
{
    /// <summary>I timestamp sono salvati in UTC e resi in ora locale: altrimenti il cambio d'ora riordina lo storico.</summary>
    public string When { get; } = session.StartedAtUtc.ToLocalTime().ToString("dd/MM/yyyy HH:mm");

    public string Freed { get; } = ViewModelBase.FormatBytes(session.BytesFreed);
    public string Items { get; } = $"{session.ItemsDeleted:N0} elementi";
    public string Categories { get; } = string.Join(", ", session.Categories.Select(c => c.CategoryId));
    public string Failed { get; } = session.ItemsFailed == 0 ? string.Empty : $"{session.ItemsFailed} falliti";
}

public sealed partial class HistoryViewModel : ViewModelBase
{
    private readonly MainWindowViewModel _main;

    public HistoryViewModel(AppServices services, MainWindowViewModel main)
    {
        _main = main;
        _ = LoadAsync(services);
    }

    public ObservableCollection<HistoryRow> Rows { get; } = [];

    private async Task LoadAsync(AppServices services)
    {
        IReadOnlyList<CleanSessionSummary> sessions =
            await services.History.GetSessionsAsync(50, CancellationToken.None);

        foreach (CleanSessionSummary session in sessions)
        {
            Rows.Add(new HistoryRow(session));
        }
    }

    [RelayCommand]
    private void Close() => _main.StartOver();
}
