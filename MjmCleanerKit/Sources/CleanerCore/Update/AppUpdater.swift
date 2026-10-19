import Foundation

/// Ciò che il modello degli aggiornamenti chiede al Core: un protocollo, così i test delle
/// Features usano un doppio.
public protocol AppUpdating: Sendable {
    var currentVersion: AppVersion { get }
    /// L'esito dell'installazione precedente, una volta sola.
    func takeInstallOutcome() -> InstallOutcome?
    /// Un aggiornamento già scaricato in una sessione precedente, verificato di nuovo.
    func cachedUpdate() async -> VerifiedUpdate?
    /// La release più recente, se è più recente della versione in uso.
    func check() async throws -> AvailableRelease?
    /// Download e verifica; `progress` riceve la frazione scaricata.
    func prepare(_ release: AvailableRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> VerifiedUpdate
    func installMode() -> InstallMode
    /// Avvia lo script di sostituzione; subito dopo l'app deve chiudersi.
    func install(_ update: VerifiedUpdate) throws
}

/// La composizione di feed, downloader, verificatore e installer per l'app in esecuzione.
public struct AppUpdater: AppUpdating {
    private let context: UpdateContext
    private let feed: any ReleaseFeed
    private let downloader: UpdateDownloader
    private let verifier: UpdateVerifier
    private let installer: UpdateInstaller

    public init(
        context: UpdateContext,
        paths: AppPaths,
        http: any HTTPClient,
        runner: any ProcessRunning,
        launcher: any DetachedLaunching
    ) {
        self.context = context
        feed = GitHubReleaseFeed(http: http, currentVersion: context.currentVersion)
        downloader = UpdateDownloader(http: http, updatesDirectory: paths.updatesDirectory)
        verifier = UpdateVerifier(runner: runner)
        installer = UpdateInstaller(context: context, updatesDirectory: paths.updatesDirectory, launcher: launcher)
    }

    public var currentVersion: AppVersion { context.currentVersion }

    public func takeInstallOutcome() -> InstallOutcome? {
        installer.takeOutcome()
    }

    public func cachedUpdate() async -> VerifiedUpdate? {
        guard let download = downloader.cached(newerThan: context.currentVersion) else { return nil }
        return try? await verifier.verify(download)
    }

    public func check() async throws -> AvailableRelease? {
        let release = try await feed.latestRelease(newerThan: context.currentVersion)
        if release == nil {
            downloader.removeTagDirectories(keeping: nil)
        }
        return release
    }

    public func prepare(_ release: AvailableRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> VerifiedUpdate {
        try await verifier.verify(try await downloader.download(release, progress: progress))
    }

    public func installMode() -> InstallMode {
        installer.mode()
    }

    public func install(_ update: VerifiedUpdate) throws {
        try installer.launch(update)
    }
}
