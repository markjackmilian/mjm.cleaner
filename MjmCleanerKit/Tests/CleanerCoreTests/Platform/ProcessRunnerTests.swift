import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Test su processi reali e innocui: argomenti senza shell, timeout, annullamento, terminazione
/// dell'intero process group.
struct ProcessRunnerTests {
    private let runner = ProcessRunner()

    @Test func passesArgumentsVerbatimWithoutAShell() async throws {
        let result = try await runner.run("/bin/echo", ["a b", "{{json .}}", "$HOME"], timeout: .seconds(5))
        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "a b {{json .}} $HOME\n")
        #expect(!result.timedOut)
    }

    @Test func resolvesBareNamesFromPathAndCapturesStandardError() async throws {
        let result = try await runner.run("ls", ["/definitely/missing"], timeout: .seconds(5))
        #expect(result.exitCode != 0)
        #expect(!result.standardError.isEmpty)
    }

    @Test func timeoutKillsTheWholeProcessGroup() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let pidFile = tmp.path + "/nipote.pid"
        let clock = ContinuousClock()
        let start = clock.now

        let result = try await runner.run("/bin/sh", ["-c", "sleep 30 & echo $! > \(pidFile); wait"], timeout: .milliseconds(300))

        #expect(result.timedOut)
        #expect(clock.now - start < .seconds(5))
        try await Task.sleep(for: .milliseconds(200))
        let grandchild = try #require(pid_t(try String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(grandchild, 0) == -1)
    }

    @Test func callerCancellationPropagatesAsCancellation() async throws {
        let clock = ContinuousClock()
        let task = Task { try await runner.run("/bin/sleep", ["30"], timeout: .seconds(60)) }
        try await Task.sleep(for: .milliseconds(200))
        let start = clock.now
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(clock.now - start < .seconds(5))
    }

    @Test func childStartsWithDefaultSignalHandling() async throws {
        let result = try await runner.run("/bin/sh", ["-c", "kill -TERM $$; echo survived"], timeout: .seconds(5))
        #expect(result.exitCode == 143)
        #expect(result.standardOutput.isEmpty)
    }

    @Test func environmentOverridesAreVisibleToTheChild() async throws {
        let result = try await runner.run("/bin/sh", ["-c", "printf %s \"$MJM_PROBE\""], timeout: .seconds(5), environment: ["MJM_PROBE": "valore"])
        #expect(result.standardOutput == "valore")
    }

    @Test func missingExecutableThrowsLaunchError() async {
        await #expect(throws: ProcessLaunchError.self) {
            _ = try await runner.run("/no/such/binary", [], timeout: .seconds(5))
        }
    }
}
