using MjmCleaner.Core.Settings;

namespace MjmCleaner.Core.Categories;

public static class CategoryCatalog
{
    private static readonly string[] All = ["*"];

    public static IReadOnlyList<CleanupCategory> Build(CleanerSettings settings, PathExpander expander)
    {
        string E(string path) => expander.Expand(path);

        return
        [
            new CleanupCategory(
                Id: "system-caches",
                DisplayName: "Cache utente e di sistema",
                Description: "Cache rigenerabili delle applicazioni e del sistema. Le app aperte potrebbero comportarsi in modo anomalo fino al riavvio.",
                Risk: RiskLevel.Medium,
                SelectedByDefault: true,
                ParentId: null,
                Rules:
                [
                    new CleanupRule(E("~/Library/Caches"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("/Library/Caches"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("$TMPDIR"), ScanMode.ClearContents, All, [], MinAge: TimeSpan.FromDays(1)),
                ]),

            new CleanupCategory(
                Id: "dev-caches",
                DisplayName: "Cache di sviluppo",
                Description: "Cache di npm, Xcode e Gradle. Tutto rigenerabile alla prossima compilazione.",
                Risk: RiskLevel.Low,
                SelectedByDefault: true,
                ParentId: null,
                Rules:
                [
                    new CleanupRule(E("~/.npm/_cacache"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("~/.cache"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("~/Library/Developer/Xcode/DerivedData"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("~/Library/Developer/Xcode/Archives"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("~/.gradle/caches"), ScanMode.ClearContents, All, []),
                ]),

            new CleanupCategory(
                Id: "nuget-packages",
                DisplayName: "Pacchetti NuGet inutilizzati",
                Description: "Svuotarla costa il ri-download di ogni pacchetto alla prossima compilazione e impedisce di compilare offline. L'età si basa sull'ultimo accesso: è un'euristica.",
                Risk: RiskLevel.Low,
                SelectedByDefault: false,
                ParentId: "dev-caches",
                Rules:
                [
                    new CleanupRule(
                        E("~/.nuget/packages"),
                        ScanMode.MatchingDirs,
                        All,
                        [],
                        MinAge: TimeSpan.FromDays(settings.NuGetMinAgeDays),
                        MaxDepth: 1),
                ]),

            new CleanupCategory(
                Id: "project-build-output",
                DisplayName: "Cartelle bin e obj nei progetti",
                Description: "Output di compilazione .NET. Una cartella viene proposta solo se accanto a essa c'è un file di progetto.",
                Risk: RiskLevel.Low,
                SelectedByDefault: true,
                ParentId: null,
                Rules:
                [
                    .. settings.ProjectRoots.Select(root => new CleanupRule(
                        E(root),
                        ScanMode.MatchingDirs,
                        ["bin", "obj"],
                        [],
                        RequiresProjectMarker: true)),
                ]),

            new CleanupCategory(
                Id: "logs",
                DisplayName: "Log e crash report",
                Description: "Diari di bordo di sistema e applicazioni.",
                Risk: RiskLevel.Low,
                SelectedByDefault: true,
                ParentId: null,
                Rules:
                [
                    new CleanupRule(E("~/Library/Logs"), ScanMode.MatchingFiles, All, [], MinAge: TimeSpan.FromDays(settings.LogsMinAgeDays)),
                    new CleanupRule(E("/Library/Logs"), ScanMode.MatchingFiles, All, [], MinAge: TimeSpan.FromDays(settings.LogsMinAgeDays)),
                ]),

            new CleanupCategory(
                Id: "trash-downloads-large",
                DisplayName: "Cestino, Download e file grandi",
                Description: "Contiene dati reali, non file rigenerabili. Ogni voce va selezionata manualmente.",
                Risk: RiskLevel.High,
                SelectedByDefault: false,
                ParentId: null,
                Rules:
                [
                    new CleanupRule(E("~/.Trash"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("~/Downloads"), ScanMode.MatchingFiles, All, [], MinAge: TimeSpan.FromDays(settings.DownloadsMinAgeDays)),
                    .. settings.LargeFileRoots.Select(root => new CleanupRule(
                        E(root),
                        ScanMode.MatchingFiles,
                        All,
                        [],
                        MinSizeBytes: settings.LargeFileThresholdBytes)),
                ]),
        ];
    }
}
