import Foundation

public protocol SettingsStoring: Sendable {
    func load() -> CleanerSettings
    func save(_ settings: CleanerSettings) throws
}

public struct SettingsStore: SettingsStoring {
    private let fileSystem: any FileSystem
    private let paths: AppPaths

    public init(fileSystem: any FileSystem, paths: AppPaths) {
        self.fileSystem = fileSystem
        self.paths = paths
    }

    /// Preferenze illeggibili o corrotte non devono impedire l'avvio: si torna ai predefiniti.
    public func load() -> CleanerSettings {
        guard fileSystem.fileExists(paths.settingsFile) else { return CleanerSettings() }
        do {
            return try JSONDecoder().decode(CleanerSettings.self, from: fileSystem.readData(paths.settingsFile))
        } catch {
            return CleanerSettings()
        }
    }

    public func save(_ settings: CleanerSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try fileSystem.createDirectory(paths.supportDirectory)
        try fileSystem.writeData(paths.settingsFile, encoder.encode(settings))
    }
}
