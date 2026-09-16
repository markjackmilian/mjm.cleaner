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
        SummaryText = $"in {report.Duration.TotalSeconds:0} secondi · " +
                       $"{report.ItemsDeleted:N0} {Plural(report.ItemsDeleted, "elemento eliminato", "elementi eliminati")}";

        // Il resoconto nomina le categorie per identificativo stabile ("project-build-output"),
        // non per il nome visualizzato: qui si traduce nel nome usato ovunque altrove nel wizard.
        // Il fallback sull'identificativo stesso è solo defensive — ogni CategoryId in un
        // CleanReport reale proviene dallo stesso catalogo interrogato da BuildCategories().
        Dictionary<string, string> displayNames = services.BuildCategories()
            .ToDictionary(c => c.Id, c => c.DisplayName, StringComparer.Ordinal);

        Rows = [.. report.Categories
            .Where(c => c.ItemsDeleted > 0)
            .Select(c => $"{displayNames.GetValueOrDefault(c.CategoryId, c.CategoryId)} — {FormatBytes(c.BytesFreed)}")];

        ErrorsText = report.ItemsFailed == 0
            ? string.Empty
            : $"{report.ItemsFailed} {Plural(report.ItemsFailed, "elemento non eliminato", "elementi non eliminati")}. {DescribeErrors(report.Errors)}";

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

    /// <summary>
    /// Riconosce un problema di permessi anche quando l'eccezione che l'ha generato non è
    /// classificata come tale nel nucleo. Misurato su questa macchina: <c>Directory.Delete</c>
    /// ricorsivo su un percorso negato da una ACL (lo stesso meccanismo dietro l'Accesso completo
    /// al disco) solleva <see cref="IOException"/>, non <see cref="UnauthorizedAccessException"/>
    /// — <c>RuleScanner.Describe</c> lo classifica quindi "InUse" (in uso), non "AccessDenied".
    /// Poiché quasi tutto ciò che l'app elimina è una directory (bin, obj, ogni figlio delle
    /// cache, i pacchetti NuGet), non riconoscerlo qui significa che l'indicazione su dove
    /// concedere il permesso non compare quasi mai. Il testo del messaggio in quel caso è
    /// letteralmente identico a quello di UnauthorizedAccessException: <c>"Access to the path
    /// '...' is denied."</c> — con il percorso incassato nel mezzo, non alla fine. Il controllo
    /// verifica quindi il FORMATO del messaggio (inizio e fine fissi), non una sottostringa
    /// libera al suo interno: una sottostringa come "denied" o, peggio, un frammento italiano
    /// come "negat" comparirebbe per caso in un normalissimo percorso utente (es. una cartella
    /// chiamata "negative-tests"), classificando come problema di permessi un errore che non lo
    /// è. Ancorare a inizio+fine rende irrilevante qualunque testo il percorso contenga in mezzo.
    /// </summary>
    private static bool LooksLikePermissionError(ScanError error)
        => error.Kind == ScanErrorKind.AccessDenied
           || (error.Message.StartsWith("Access to the path", StringComparison.Ordinal)
               && error.Message.EndsWith("is denied.", StringComparison.Ordinal));

    private static string DescribeErrors(IReadOnlyList<ScanError> errors)
    {
        if (errors.Any(LooksLikePermissionError))
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
