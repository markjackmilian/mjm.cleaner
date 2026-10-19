import Foundation

/// I dati dell'applicazione vivono sotto Application Support, che la deny-list protegge:
/// l'applicazione non può eliminare il proprio storico.
public struct AppPaths: Sendable, Equatable {
    public let supportDirectory: String

    public init(supportDirectory: String) {
        self.supportDirectory = supportDirectory
    }

    public var databaseFile: String { PathText.join(supportDirectory, "history.db") }
    public var settingsFile: String { PathText.join(supportDirectory, "settings.json") }
    public var logsDirectory: String { PathText.join(supportDirectory, "logs") }
    /// Download, bundle estratti ed esito dell'ultima installazione degli aggiornamenti. Non sta in
    /// `~/Library/Caches`: la categoria «Cache di sistema» dell'app la cancellerebbe.
    public var updatesDirectory: String { PathText.join(supportDirectory, "updates") }

    /// `~/Library/Application Support/<bundle id>/`, ricavata da Foundation: diversa dalla
    /// `mjm.cleaner/` dell'app C#, così le due app convivono. In fase 2, sotto sandbox, la stessa
    /// chiamata punterà da sola al container dell'app.
    public static func forBundleIdentifier(_ bundleIdentifier: String) -> AppPaths {
        let directory = URL.applicationSupportDirectory
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .path(percentEncoded: false)
        return AppPaths(supportDirectory: PathText.trimmingTrailingSlashes(directory))
    }
}
