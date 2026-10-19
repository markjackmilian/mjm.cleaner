/// Ciò che l'updater sa dell'app in esecuzione. Esiste solo per la build Release: le build Debug
/// (`com.mjm.cleaner.debug`) e la demo non si aggiornano mai, così una build di sviluppo non viene
/// sostituita da quella pubblicata.
public struct UpdateContext: Sendable, Equatable {
    public static let releaseBundleIdentifier = "com.mjm.cleaner"

    public let currentVersion: AppVersion
    /// Il bundle `.app` in esecuzione, quello che l'installazione sostituisce.
    public let bundlePath: String
    /// Il PID dell'app: lo script di sostituzione attende che termini.
    public let processIdentifier: Int32

    public init(currentVersion: AppVersion, bundlePath: String, processIdentifier: Int32) {
        self.currentVersion = currentVersion
        self.bundlePath = bundlePath
        self.processIdentifier = processIdentifier
    }

    /// `nil` per ogni bundle id diverso da quello della release e per una versione illeggibile. Il
    /// percorso perde la `/` finale che `Bundle.main.bundleURL` aggiunge alle cartelle.
    public static func make(
        bundleIdentifier: String?,
        shortVersion: String?,
        bundlePath: String,
        processIdentifier: Int32
    ) -> UpdateContext? {
        guard bundleIdentifier == releaseBundleIdentifier,
              let shortVersion, let version = AppVersion(shortVersion) else { return nil }
        return UpdateContext(
            currentVersion: version, bundlePath: PathText.trimmingTrailingSlashes(bundlePath), processIdentifier: processIdentifier)
    }
}
