import Foundation

/// Preferenze persistite in `settings.json`. Chiavi e valori predefiniti identici al C#; un campo
/// mancante prende il valore predefinito, un campo di tipo sbagliato rende il file illeggibile
/// (e `SettingsStore` torna ai predefiniti), tranne l'aspetto, che è tollerante.
public struct CleanerSettings: Sendable, Equatable, Codable {
    public var projectRoots: [String] = []
    public var largeFileRoots: [String] = []
    public var largeFileThresholdBytes: Int64 = 500 * 1024 * 1024
    /// Cartelle mai analizzate né proposte, in nessuna categoria della pulizia guidata.
    public var excludedFolders: [String] = []
    public var downloadsMinAgeDays = 90
    public var logsMinAgeDays = 30
    public var nuGetMinAgeDays = 180
    /// Selezione dell'ultimo utilizzo: riduce il costo dei quattro passi nella pulizia di routine.
    public var selectedCategoryIds = ["system-caches", "dev-caches", "project-build-output", "logs"]
    public var appearance = AppearancePreference.auto
    /// Controllo automatico delle release su GitHub: all'avvio e ogni 24 ore.
    public var automaticUpdateChecks = true
    /// L'ultimo controllo riuscito (con o senza novità); `nil` finché non ce n'è stato uno.
    public var lastUpdateCheck: Date?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case projectRoots = "ProjectRoots"
        case largeFileRoots = "LargeFileRoots"
        case largeFileThresholdBytes = "LargeFileThresholdBytes"
        case excludedFolders = "ExcludedFolders"
        case downloadsMinAgeDays = "DownloadsMinAgeDays"
        case logsMinAgeDays = "LogsMinAgeDays"
        case nuGetMinAgeDays = "NuGetMinAgeDays"
        case selectedCategoryIds = "SelectedCategoryIds"
        case appearance = "Appearance"
        case automaticUpdateChecks = "AutomaticUpdateChecks"
        case lastUpdateCheck = "LastUpdateCheck"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CleanerSettings()
        projectRoots = try container.decodeIfPresent([String].self, forKey: .projectRoots) ?? defaults.projectRoots
        largeFileRoots = try container.decodeIfPresent([String].self, forKey: .largeFileRoots) ?? defaults.largeFileRoots
        largeFileThresholdBytes = try container.decodeIfPresent(Int64.self, forKey: .largeFileThresholdBytes) ?? defaults.largeFileThresholdBytes
        excludedFolders = try container.decodeIfPresent([String].self, forKey: .excludedFolders) ?? defaults.excludedFolders
        downloadsMinAgeDays = try container.decodeIfPresent(Int.self, forKey: .downloadsMinAgeDays) ?? defaults.downloadsMinAgeDays
        logsMinAgeDays = try container.decodeIfPresent(Int.self, forKey: .logsMinAgeDays) ?? defaults.logsMinAgeDays
        nuGetMinAgeDays = try container.decodeIfPresent(Int.self, forKey: .nuGetMinAgeDays) ?? defaults.nuGetMinAgeDays
        selectedCategoryIds = try container.decodeIfPresent([String].self, forKey: .selectedCategoryIds) ?? defaults.selectedCategoryIds
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? defaults.appearance
        automaticUpdateChecks = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecks) ?? defaults.automaticUpdateChecks
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck) ?? defaults.lastUpdateCheck
    }
}
