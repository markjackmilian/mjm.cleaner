import Testing
@testable import CleanerCore

struct XcodeCleanupServiceTests {
    private struct ProcessListingRunner: ProcessRunning {
        let outcome: Result<ProcessResult, any Error>

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            try outcome.get()
        }
    }

    @Test(arguments: [
        ("/Applications/Xcode.app/Contents/MacOS/Xcode", XcodeRunningState.running),
        ("/Applications/Xcode-beta.app/Contents/MacOS/Xcode-beta", .running),
        ("/usr/bin/simctl", .notRunning),
    ])
    func runningProbeClassifiesProcessListing(processPath: String, expected: XcodeRunningState) async throws {
        let probe = XcodeRunningProbe(runner: ProcessListingRunner(
            outcome: .success(ProcessResult(exitCode: 0, standardOutput: processPath, standardError: "", timedOut: false))))

        #expect(try await probe.state() == expected)
    }

    @Test func runningProbeReturnsUnknownWhenListingFails() async throws {
        let probe = XcodeRunningProbe(runner: ProcessListingRunner(
            outcome: .success(ProcessResult(exitCode: 1, standardOutput: "", standardError: "denied", timedOut: false))))

        #expect(try await probe.state() == .unknown)
    }

    // Solo Swift: timeout, avvio fallito e stderr non vuoto non vengono mai scambiati per
    // «Xcode chiuso», anche quando lo stdout elenca processi qualunque.
    @Test(arguments: [
        Result<ProcessResult, any Error>.success(ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true)),
        .success(ProcessResult(exitCode: 0, standardOutput: "/usr/bin/simctl", standardError: "ps: warning", timedOut: false)),
        .failure(ProcessLaunchError(executable: "ps", code: 2)),
    ])
    func runningProbeIsUnknownWhenTheListingIsNotReliable(outcome: Result<ProcessResult, any Error>) async throws {
        let probe = XcodeRunningProbe(runner: ProcessListingRunner(outcome: outcome))

        #expect(try await probe.state() == .unknown)
    }
}
