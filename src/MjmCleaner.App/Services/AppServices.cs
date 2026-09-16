using System.IO.Abstractions;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Diagnostics;
using MjmCleaner.Core.History;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App.Services;

/// <summary>
/// Composizione manuale delle dipendenze: per un'applicazione con un solo grafo di
/// oggetti un contenitore di inversione del controllo aggiungerebbe solo indirezione.
/// </summary>
public sealed class AppServices
{
    /// <summary>
    /// Pubblico (non solo tramite <see cref="CreateAsync"/>) perché consente di comporre
    /// un'istanza con una singola dipendenza sostituita da un finto — ad esempio un
    /// <see cref="IScanEngine"/> che fallisce deliberatamente — riusando per il resto le
    /// dipendenze reali di un'istanza creata da <see cref="CreateAsync"/>. Non cambia il percorso
    /// di produzione, che continua a passare da <see cref="CreateAsync"/>.
    /// </summary>
    public AppServices(
        IScanEngine scan,
        ICleanEngine clean,
        IHistoryStore history,
        ISessionLogWriter sessionLog,
        ISettingsStore settings,
        IRunningAppsProbe runningApps,
        AppPaths paths)
    {
        Scan = scan;
        Clean = clean;
        History = history;
        SessionLog = sessionLog;
        Settings = settings;
        RunningApps = runningApps;
        Paths = paths;
    }

    public IScanEngine Scan { get; }
    public ICleanEngine Clean { get; }
    public IHistoryStore History { get; }
    public ISessionLogWriter SessionLog { get; }
    public ISettingsStore Settings { get; }
    public IRunningAppsProbe RunningApps { get; }
    public AppPaths Paths { get; }

    public IReadOnlyList<CleanupCategory> BuildCategories()
        => CategoryCatalog.Build(Settings.Load(), PathExpander.ForCurrentUser());

    public static async Task<AppServices> CreateAsync()
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        FileSystem fileSystem = new();
        AppPaths paths = AppPaths.ForCurrentUser();

        FileSystemLinkInspector links = new(fileSystem);
        PathGuard guard = new(new DenyList(home), links, home);
        RuleScanner scanner = new(fileSystem, guard, links, TimeProvider.System);

        HistoryStore history = new(paths.DatabaseFile);
        await history.InitializeAsync(CancellationToken.None);

        return new AppServices(
            new ScanEngine(scanner),
            new CleanEngine(fileSystem, guard, TimeProvider.System),
            history,
            new SessionLogWriter(fileSystem, paths),
            new SettingsStore(fileSystem, paths),
            RunningAppsProbe.ForCurrentMachine(),
            paths);
    }
}
