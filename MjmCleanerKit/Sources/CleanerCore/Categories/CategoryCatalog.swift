import Foundation

public enum CategoryCatalog {
    private static let all = ["*"]

    public static func build(_ settings: CleanerSettings, _ expander: PathExpander) -> [CleanupCategory] {
        func expanded(_ path: String) -> String { expander.expand(path) }
        func days(_ count: Int) -> TimeInterval { TimeInterval(count) * 86_400 }
        // Le cartelle escluse valgono per ogni regola del wizard (spec
        // `2026-10-19-large-files-exclusions-design.md`).
        let excluded = settings.excludedFolders.map(expanded)

        return [
            CleanupCategory(
                id: "system-caches",
                displayName: String(localized: "Cache utente e di sistema", bundle: .module),
                description: String(localized: "Cache rigenerabili delle applicazioni e del sistema. Le app aperte potrebbero comportarsi in modo anomalo fino al riavvio.", bundle: .module),
                risk: .medium,
                selectedByDefault: true,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/Library/Caches"), .clearContents, include: all, exclude: []),
                    CleanupRule(expanded("/Library/Caches"), .clearContents, include: all, exclude: []),
                    CleanupRule(expanded("$TMPDIR"), .clearContents, include: all, exclude: [], minAge: days(1)),
                ]),

            CleanupCategory(
                id: "dev-caches",
                displayName: String(localized: "Cache di sviluppo", bundle: .module),
                description: String(localized: "Cache di npm e Gradle. Xcode DerivedData si gestisce dalla pagina Xcode dedicata.", bundle: .module),
                risk: .low,
                selectedByDefault: true,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/.npm/_cacache"), .clearContents, include: all, exclude: []),
                    CleanupRule(expanded("~/.cache"), .clearContents, include: all, exclude: []),
                    // Niente regola su "Archives": a differenza di DerivedData (output di
                    // compilazione, rigenerabile), un archivio Xcode contiene il binario e il dSYM
                    // di una build già spedita. Senza quel dSYM non si simbolicano più i crash
                    // report di quella release.
                    CleanupRule(expanded("~/.gradle/caches"), .clearContents, include: all, exclude: []),
                ]),

            CleanupCategory(
                id: "nuget-packages",
                displayName: String(localized: "Pacchetti NuGet inutilizzati", bundle: .module),
                description: String(localized: "Svuotarla costa il ri-download di ogni pacchetto alla prossima compilazione e impedisce di compilare offline. L'età si basa sull'ultimo accesso: è un'euristica.", bundle: .module),
                risk: .low,
                selectedByDefault: false,
                parentId: "dev-caches",
                rules: [
                    CleanupRule(
                        expanded("~/.nuget/packages"), .matchingDirs, include: all, exclude: [],
                        minAge: days(settings.nuGetMinAgeDays), maxDepth: 1),
                ]),

            CleanupCategory(
                id: "project-build-output",
                displayName: String(localized: "Cartelle bin e obj nei progetti", bundle: .module),
                description: String(localized: "Output di compilazione .NET. Una cartella viene proposta solo se accanto a essa c'è un file di progetto.", bundle: .module),
                risk: .low,
                selectedByDefault: true,
                parentId: nil,
                rules: settings.projectRoots.map { root in
                    CleanupRule(expanded(root), .matchingDirs, include: ["bin", "obj"], exclude: [], requiresProjectMarker: true)
                }),

            CleanupCategory(
                id: "logs",
                displayName: String(localized: "Log e crash report", bundle: .module),
                description: String(localized: "Diari di bordo di sistema e applicazioni.", bundle: .module),
                risk: .low,
                selectedByDefault: true,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/Library/Logs"), .matchingFiles, include: all, exclude: [], minAge: days(settings.logsMinAgeDays)),
                    CleanupRule(expanded("/Library/Logs"), .matchingFiles, include: all, exclude: [], minAge: days(settings.logsMinAgeDays)),
                ]),

            CleanupCategory(
                id: "trash",
                displayName: String(localized: "Cestino", bundle: .module),
                description: String(localized: "Contiene dati reali, non file rigenerabili. Va selezionato manualmente.", bundle: .module),
                risk: .high,
                selectedByDefault: false,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/.Trash"), .clearContents, include: all, exclude: []),
                ]),

            CleanupCategory(
                id: "downloads",
                displayName: String(localized: "Download", bundle: .module),
                description: String(localized: "File in Download non usati da tempo. Contiene dati reali: nella verifica ogni voce parte deselezionata.", bundle: .module),
                risk: .high,
                selectedByDefault: false,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/Downloads"), .matchingFiles, include: all, exclude: [], minAge: days(settings.downloadsMinAgeDays)),
                ],
                itemsSelectedByDefault: false),

            // Separata dai Download (2026-10-19): nello stesso gruppo i file grandi si confondevano
            // con i download, e fra loro c'erano i dischi delle macchine virtuali.
            CleanupCategory(
                id: "large-files",
                displayName: String(localized: "File grandi", bundle: .module),
                description: String(localized: "File e pacchetti oltre la soglia, nelle cartelle scelte nelle Impostazioni. Contiene dati reali: nella verifica ogni voce parte deselezionata.", bundle: .module),
                risk: .high,
                selectedByDefault: false,
                parentId: nil,
                rules: settings.largeFileRoots.map { root in
                    CleanupRule(expanded(root), .matchingFiles, include: all, exclude: [], minSizeBytes: settings.largeFileThresholdBytes)
                },
                itemsSelectedByDefault: false),
        ].map { $0.excluding(excluded) }
    }
}
