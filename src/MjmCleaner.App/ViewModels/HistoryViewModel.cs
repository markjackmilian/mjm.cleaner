using System.Collections.ObjectModel;
using System.Globalization;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.History;

namespace MjmCleaner.App.ViewModels;

public sealed class HistoryRow(CleanSessionSummary session, IReadOnlyDictionary<string, string> names)
{
    private static readonly CultureInfo Italian = new("it-IT");

    /// <summary>I timestamp sono salvati in UTC e resi in ora locale: altrimenti il cambio d'ora riordina lo storico.</summary>
    public string When { get; } = session.StartedAtUtc.ToLocalTime().ToString("d MMM yyyy, HH:mm", Italian);

    public long BytesFreed { get; } = session.BytesFreed;
    public string Freed { get; } = ViewModelBase.FormatBytes(session.BytesFreed);
    public string Items { get; } = session.ItemsDeleted.ToString("N0", Italian);
    public IReadOnlyList<string> CategoryNames { get; } =
        [.. session.Categories.Select(c => names.GetValueOrDefault(c.CategoryId, c.CategoryId))];
    public string Failed { get; } = session.ItemsFailed == 0 ? string.Empty : $"{session.ItemsFailed} falliti";
}

public sealed partial class HistoryViewModel : ViewModelBase
{
    private readonly MainWindowViewModel _main;

    [ObservableProperty] private string _totalText = "—";
    [ObservableProperty] private string _countText = string.Empty;

    public HistoryViewModel(AppServices services, MainWindowViewModel main)
    {
        _main = main;
        _ = LoadAsync(services);
    }

    public ObservableCollection<HistoryRow> Rows { get; } = [];

    public static string Summarize(int count) => count switch
    {
        0 => "nessuna pulizia",
        1 => "in 1 pulizia",
        _ => $"in {count} pulizie",
    };

    private async Task LoadAsync(AppServices services)
    {
        IReadOnlyList<CleanSessionSummary> sessions =
            await services.History.GetSessionsAsync(50, CancellationToken.None);
        IReadOnlyDictionary<string, string> names = ViewModels.CategoryNames.Build(services.BuildCategories());

        foreach (CleanSessionSummary session in sessions)
        {
            Rows.Add(new HistoryRow(session, names));
        }

        TotalText = FormatBytes(Rows.Sum(r => r.BytesFreed));
        CountText = Summarize(Rows.Count);
    }

    [RelayCommand]
    private void Close() => _main.StartOver();
}
