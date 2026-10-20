#if DEBUG
import CleanerCore
import CleanerFeatures
import Foundation
import Synchronization

/// I servizi finti dell'avvio dimostrativo: rispondono con `DemoData` e non leggono né scrivono
/// mai il disco. Lo storico e le impostazioni restano in memoria.
enum DemoServices {
    static let paths = AppPaths(supportDirectory: "/Users/demo/Library/Application Support/com.mjm.cleaner")

    static func environment(page: DemoLaunch.Page, appearance: AppearancePreference) throws -> AppEnvironment {
        var settings = CleanerSettings()
        settings.appearance = appearance
        settings.projectRoots = ["~/Progetti", "~/Lavoro/clienti"]
        settings.largeFileRoots = ["~/Downloads", "~/Macchine virtuali"]
        settings.excludedFolders = ["~/Lavoro/archivio"]
        return AppEnvironment(
            scan: DemoScan(),
            clean: DemoClean(),
            history: DemoHistory(),
            sessionLog: DemoSessionLog(),
            settings: DemoSettings(settings),
            runningApps: DemoRunningApps(),
            docker: DemoDocker(available: page != .dockerUnavailable),
            xcode: DemoXcode(),
            paths: paths,
            clock: SystemWallClock(),
            // L'espansione di «~» è solo testo: serve alle regole delle categorie, non al disco.
            expander: try PathExpander(homeDirectory: "/Users/demo", tempDirectory: "/private/var/folders/demo/T"))
    }
}

/// Segnala l'avanzamento delle prime categorie e poi resta in analisi finché non si annulla.
private struct DemoScan: ScanPerforming {
    func scan(_ categories: [CleanupCategory], progress: (@Sendable (ScanProgress) -> Void)?) async throws -> [CategoryScanResult] {
        for update in DemoData.scanProgress {
            progress?(update)
        }
        try await Task.sleep(for: .seconds(3600))
        return DemoData.scanResults
    }
}

private struct DemoClean: CleanPerforming {
    func clean(
        _ selections: [CategorySelection],
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> CleanReport {
        DemoData.cleanReport
    }
}

private final class DemoHistory: HistoryStoring {
    private let saved = Mutex<Int64>(0)

    func initialize() async throws {}

    func save(_ report: CleanReport) async throws -> Int64 {
        saved.withLock { count in
            count += 1
            return Int64(DemoData.sessions.count) + count
        }
    }

    func sessions(limit: Int) async throws -> [CleanSessionSummary] {
        Array(DemoData.sessions.prefix(limit))
    }

    func totalBytesFreed() async throws -> Int64 {
        DemoData.sessions.reduce(0) { $0 + $1.bytesFreed }
    }
}

private struct DemoSessionLog: SessionLogWriting {
    func write(sessionId: Int64, report: CleanReport) async throws {}
    func openJournal(startedAt: Date) -> PendingJournal? { nil }
    func discard(_ journal: PendingJournal) {}
}

private final class DemoSettings: SettingsStoring {
    private let current: Mutex<CleanerSettings>

    init(_ settings: CleanerSettings) {
        current = Mutex(settings)
    }

    func load() -> CleanerSettings {
        current.withLock { $0 }
    }

    func save(_ settings: CleanerSettings) throws {
        current.withLock { $0 = settings }
    }
}

private struct DemoRunningApps: RunningAppsProbing {
    func affectedApps(_ paths: [String]) async -> [String] {
        ["Google Chrome"]
    }
}

private struct DemoDocker: DockerCleanupServing {
    let available: Bool

    func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        guard available else { throw DockerUnavailableError(DockerUnavailableError.notRunning) }
        return DemoData.dockerAnalysis
    }

    func execute(_ selected: [DockerCandidate], on target: DockerTarget, progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        DemoData.dockerResult
    }

    func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        DemoData.diskAfter
    }
}

private struct DemoXcode: XcodeCleanupServing {
    func analyze() async throws -> XcodeSnapshot {
        DemoData.xcodeSnapshot
    }

    func execute(
        _ plan: XcodeConfirmedPlan,
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> XcodeCleanResult {
        DemoData.xcodeResult
    }
}
#endif
