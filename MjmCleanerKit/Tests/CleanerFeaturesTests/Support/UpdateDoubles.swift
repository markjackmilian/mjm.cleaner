import CleanerCore
import CleanerFeatures
import Foundation
import Synchronization
import Testing

/// Updater finto: risponde con i valori impostati e conta le chiamate. Con `holdChecks` il
/// controllo resta sospeso finché il test non apre `checkReleased`.
final class FakeUpdater: AppUpdating {
    private struct State {
        var outcome: InstallOutcome?
        var cached: VerifiedUpdate?
        var check: Result<AvailableRelease?, UpdateError> = .success(nil)
        var prepare: Result<VerifiedUpdate, UpdateError>?
        var mode = InstallMode.inPlace
        var installFailure: UpdateError?
        var checks = 0
        var installs: [VerifiedUpdate] = []
        var holdChecks = false
        var holdPrepare = false
        var lastProgress: (@Sendable (Double) -> Void)?
    }

    private let state = Mutex(State())
    let checkStarted = Gate<Void>()
    let checkReleased = Gate<Void>()
    let prepareStarted = Gate<Void>()
    let prepareReleased = Gate<Void>()

    var currentVersion: AppVersion { AppVersion(major: 0, minor: 1, patch: 0) }

    var checks: Int { state.withLock { $0.checks } }
    var installs: [VerifiedUpdate] { state.withLock { $0.installs } }

    func setOutcome(_ outcome: InstallOutcome?) { state.withLock { $0.outcome = outcome } }
    func setCached(_ update: VerifiedUpdate?) { state.withLock { $0.cached = update } }
    func setCheck(_ result: Result<AvailableRelease?, UpdateError>) { state.withLock { $0.check = result } }
    func setPrepare(_ result: Result<VerifiedUpdate, UpdateError>) { state.withLock { $0.prepare = result } }
    func setMode(_ mode: InstallMode) { state.withLock { $0.mode = mode } }
    func failInstalls(with error: UpdateError) { state.withLock { $0.installFailure = error } }
    func holdChecks() { state.withLock { $0.holdChecks = true } }
    func holdPrepare() { state.withLock { $0.holdPrepare = true } }

    /// Richiama l'ultima `progress` ricevuta da `prepare`, come farebbe il download in corso.
    func sendProgress(_ fraction: Double) {
        let progress = state.withLock { $0.lastProgress }
        progress?(fraction)
    }

    func takeInstallOutcome() -> InstallOutcome? {
        state.withLock { state in
            defer { state.outcome = nil }
            return state.outcome
        }
    }

    func cachedUpdate() async -> VerifiedUpdate? {
        state.withLock { $0.cached }
    }

    func check() async throws -> AvailableRelease? {
        let (result, hold) = state.withLock { state in
            state.checks += 1
            return (state.check, state.holdChecks)
        }
        checkStarted.open()
        if hold { try await checkReleased.wait() }
        return try result.get()
    }

    func prepare(_ release: AvailableRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> VerifiedUpdate {
        let (result, hold) = state.withLock { state -> (Result<VerifiedUpdate, UpdateError>, Bool) in
            state.lastProgress = progress
            return (state.prepare ?? .success(VerifiedUpdate(release: release, bundlePath: "/tmp/updates/\(release.tag)/expanded/mjm.cleaner.app")), state.holdPrepare)
        }
        progress(0.5)
        prepareStarted.open()
        if hold { try await prepareReleased.wait() }
        return try result.get()
    }

    func installMode() -> InstallMode {
        state.withLock { $0.mode }
    }

    func install(_ update: VerifiedUpdate) throws {
        try state.withLock { state in
            if let failure = state.installFailure { throw failure }
            state.installs.append(update)
        }
    }
}

/// Orologio che si sposta solo con `advance`, per i test che attraversano le 24 ore.
final class SteppedClock: WallClock {
    private let current: Mutex<Date>

    init(_ start: Date) {
        current = Mutex(start)
    }

    var now: Date { current.withLock { $0 } }

    func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

@MainActor
final class FakeUpdateHost: UpdateHosting {
    private(set) var terminations = 0
    private(set) var revealed: [String] = []
    private(set) var opened: [URL] = []

    func terminate() { terminations += 1 }
    func reveal(_ path: String) { revealed.append(path) }
    func open(_ url: URL) { opened.append(url) }
}

/// Una release `v0.2.0` per i test dei modelli.
func makeRelease(_ tag: String = "v0.2.0") -> AvailableRelease {
    let version = AppVersion(tag) ?? AppVersion(major: 0, minor: 2, patch: 0)
    let name = AvailableRelease.assetName(for: tag)
    return AvailableRelease(
        version: version,
        pageURL: URL(fileURLWithPath: "/").appending(path: "release-\(tag)"),
        assetName: name,
        assetURL: URL(fileURLWithPath: "/").appending(path: name),
        size: 10,
        sha256: String(repeating: "a", count: 64))
}

func makeVerified(_ tag: String = "v0.2.0") -> VerifiedUpdate {
    VerifiedUpdate(release: makeRelease(tag), bundlePath: "/tmp/updates/\(tag)/expanded/mjm.cleaner.app")
}
