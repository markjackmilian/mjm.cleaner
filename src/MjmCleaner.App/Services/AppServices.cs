using System.IO.Abstractions;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Diagnostics;
using MjmCleaner.Core.Docker;
using MjmCleaner.Core.History;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Settings;
using MjmCleaner.Core.Xcode;

namespace MjmCleaner.App.Services;

/// <summary>
/// Composizione manuale delle dipendenze: per un'applicazione con un solo grafo di
/// oggetti un contenitore di inversione del controllo aggiungerebbe solo indirezione.
/// </summary>
public sealed class AppServices
{
    private AppServices(
        IScanEngine scan,
        ICleanEngine clean,
        IHistoryStore history,
        ISessionLogWriter sessionLog,
        ISettingsStore settings,
        IRunningAppsProbe runningApps,
        DockerCleanupService docker,
        IXcodeCleanupService xcode,
        AppPaths paths)
    {
        Scan = scan;
        Clean = clean;
        History = history;
        SessionLog = sessionLog;
        Settings = settings;
        RunningApps = runningApps;
        Docker = docker;
        Xcode = xcode;
        Paths = paths;
    }

    public IScanEngine Scan { get; }
    public ICleanEngine Clean { get; }
    public IHistoryStore History { get; }
    public ISessionLogWriter SessionLog { get; }
    public ISettingsStore Settings { get; }
    public IRunningAppsProbe RunningApps { get; }
    public DockerCleanupService Docker { get; }
    public IXcodeCleanupService Xcode { get; }
    public AppPaths Paths { get; }

    public IReadOnlyList<CleanupCategory> BuildCategories()
        => CategoryCatalog.Build(Settings.Load(), PathExpander.ForCurrentUser());

    /// <summary>Le stesse cartelle progetto di bin/obj, espanse: dove cercare le immagini citate.</summary>
    public IReadOnlyList<string> ExpandedProjectRoots()
    {
        PathExpander expander = PathExpander.ForCurrentUser();
        return [.. Settings.Load().ProjectRoots.Select(expander.Expand)];
    }

    /// <param name="paths">Posizione dei dati dell'app; solo i test la sostituiscono, per non toccare quelli reali.</param>
    public static async Task<AppServices> CreateAsync(AppPaths? paths = null)
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        FileSystem fileSystem = new();
        paths ??= AppPaths.ForCurrentUser();

        FileSystemLinkInspector links = new(fileSystem);
        PathGuard guard = new(new DenyList(home), links, home);
        RuleScanner scanner = new(fileSystem, guard, links, TimeProvider.System);

        // Docker passa solo dalla CLI: nessun file sotto la cartella di Docker Desktop viene mai
        // cancellato (la deny-list resta invariata); di Docker.raw si legge soltanto la dimensione.
        ProcessRunner processes = new();
        DockerCli dockerCli = new(processes, DockerBinaryLocator.Find(fileSystem, home));
        DockerCleanupService docker = new(
            new DockerInventoryCollector(dockerCli, fileSystem),
            new ProjectReferenceScanner(fileSystem),
            new DiskUsageProbe(processes, fileSystem, DiskUsageProbe.DefaultPath(home)),
            new DockerCleanExecutor(dockerCli, TimeProvider.System));

        XcodeCli xcodeCli = new(processes, fileSystem.File.Exists("/usr/bin/xcrun") ? "/usr/bin/xcrun" : null);
        XcodeSizeProbe xcodeMeasures = new(fileSystem, processes, links, home);
        XcodeFileScanner xcodeFiles = new(fileSystem, scanner, guard, links, xcodeMeasures, home);
        XcodeInventoryCollector xcodeInventory = new(xcodeCli, xcodeFiles);
        XcodeRunningProbe xcodeRunning = new(processes);
        XcodeCleanupService xcode = new(xcodeInventory, xcodeRunning,
            new XcodeCleanExecutor(xcodeCli, xcodeInventory, new CleanEngine(fileSystem, guard, TimeProvider.System), xcodeMeasures, xcodeRunning, TimeProvider.System));

        HistoryStore history = new(paths.DatabaseFile);
        await history.InitializeAsync(CancellationToken.None);

        return new AppServices(
            new ScanEngine(scanner),
            new CleanEngine(fileSystem, guard, TimeProvider.System),
            history,
            new SessionLogWriter(fileSystem, paths),
            new SettingsStore(fileSystem, paths),
            RunningAppsProbe.ForCurrentMachine(),
            docker,
            xcode,
            paths);
    }
}
