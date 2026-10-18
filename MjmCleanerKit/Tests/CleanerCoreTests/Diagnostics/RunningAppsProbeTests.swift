import Foundation
import Testing
@testable import CleanerCore

struct RunningAppsProbeTests {
    private func create(_ processes: String...) -> RunningAppsProbe {
        RunningAppsProbe(processNames: { processes })
    }

    @Test func matchesBundleIdentifierAgainstProcessName() async {
        #expect(await create("Safari", "Finder").affectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]) == ["Safari"])
    }

    @Test func ignoresProcessesNotInvolved() async {
        #expect(await create("Mail").affectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]).isEmpty)
    }

    @Test func reportsEachApplicationOnlyOnce() async {
        let affected = await create("Safari").affectedApps([
            "/Users/tester/Library/Caches/com.apple.Safari",
            "/Users/tester/Library/Caches/com.apple.Safari.WebKit",
        ])
        #expect(affected == ["Safari"])
    }

    @Test func ignoresVeryShortProcessNamesToAvoidFalsePositives() async {
        #expect(await create("ls").affectedApps(["/Users/tester/Library/Caches/com.apple.Tools"]).isEmpty)
    }

    // Confronto per parole intere, non per sottostringa: "Dock" (macOS Dock) non deve
    // corrispondere a "com.docker.docker" né a "Docker Desktop".
    @Test(arguments: [
        ("Safari", "/Users/tester/Library/Caches/com.apple.Safari", true),
        ("Google Chrome", "/Users/tester/Library/Caches/com.google.Chrome", true),
        ("Docker", "/Users/tester/Library/Caches/Docker Desktop", true),
        ("Dock", "/Users/tester/Library/Caches/com.docker.docker", false),
        ("Dock", "/Users/tester/Library/Caches/Docker Desktop", false),
    ])
    func matchesWholeWordsNotSubstrings(processName: String, path: String, expectMatch: Bool) async {
        let affected = await create(processName).affectedApps([path])
        #expect(affected == (expectMatch ? [processName] : []))
    }

    @Test func systemDaemonsDoNotMatchRealisticCacheFolders() async {
        let affected = await create("accountsd", "secd", "tipsd").affectedApps([
            "/Users/tester/Library/Caches/com.apple.Safari",
            "/Users/tester/Library/Caches/com.google.Chrome",
            "/Users/tester/Library/Caches/JetBrains",
            "/Users/tester/Library/Caches/Homebrew",
            "/Users/tester/Library/Caches/Docker Desktop",
        ])
        #expect(affected.isEmpty)
    }

    @Test func reportsFullProcessNameWhenOnlyOneWordMatches() async {
        #expect(await create("Docker Desktop").affectedApps(["/Users/tester/Library/Caches/Docker"]) == ["Docker Desktop"])
    }

    @Test(arguments: [
        ("/Applications/Safari.app/Contents/MacOS/Safari", "Safari"),
        ("/System/Applications/Calendar.app/Contents/MacOS/Calendar", "Calendar"),
    ])
    func extractApplicationNamesRecognizesSimpleBundlesInStandardLocations(path: String, expectedName: String) {
        #expect(RunningAppsProbe.extractApplicationNames([path]) == [expectedName])
    }

    @Test func extractApplicationNamesRecognizesBundlesUnderTheUserHomeDirectory() {
        let home = NSHomeDirectory()
        let path = "\(home)/Applications/HomeBrewedApp.app/Contents/MacOS/HomeBrewedApp"
        #expect(RunningAppsProbe.extractApplicationNames([path], home: home) == ["HomeBrewedApp"])
    }

    @Test func extractApplicationNamesReturnsTheOutermostBundleNameForNestedHelperProcesses() {
        let names = RunningAppsProbe.extractApplicationNames([
            "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)",
        ])
        #expect(names == ["Claude"])
    }

    @Test(arguments: [
        "/usr/libexec/secd",
        "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
        "",
        "   ",
        "not a path at all",
    ])
    func extractApplicationNamesDiscardsPathsOutsideUserFacingApplications(path: String) {
        #expect(RunningAppsProbe.extractApplicationNames([path]).isEmpty)
    }

    @Test func extractApplicationNamesIgnoresRealisticSystemDaemonPaths() {
        let names = RunningAppsProbe.extractApplicationNames([
            "/usr/libexec/secd",
            "/System/Library/Frameworks/Accounts.framework/Versions/A/Support/accountsd",
            "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
        ])
        #expect(names.isEmpty)
    }

    // MARK: - Nuovi: raccolta tramite ProcessRunning

    private struct FakeProcessRunner: ProcessRunning {
        let outcome: Result<ProcessResult, any Error>

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            #expect(executable == "ps")
            #expect(arguments == ["-axo", "comm="])
            return try outcome.get()
        }
    }

    @Test func forCurrentMachineReadsApplicationNamesFromPs() async {
        let output = """
            /usr/libexec/secd
            /Applications/Safari.app/Contents/MacOS/Safari
              /Applications/Mail.app/Contents/MacOS/Mail\u{20}\u{20}

            """
        let probe = RunningAppsProbe.forCurrentMachine(
            runner: FakeProcessRunner(outcome: .success(ProcessResult(exitCode: 0, standardOutput: output, standardError: "", timedOut: false))),
            home: "/Users/tester")

        #expect(await probe.affectedApps(["/Users/tester/Library/Caches/com.apple.Safari", "/Users/tester/Library/Caches/com.apple.mail"]) == ["Mail", "Safari"])
    }

    // Un avviso che non si può calcolare non deve mai impedire una pulizia.
    @Test(arguments: [
        Result<ProcessResult, any Error>.success(ProcessResult(exitCode: 1, standardOutput: "/Applications/Safari.app/Contents/MacOS/Safari", standardError: "", timedOut: false)),
        .success(ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true)),
        .failure(ProcessLaunchError(executable: "ps", code: 2)),
    ])
    func forCurrentMachineDegradesToNoWarningOnFailure(outcome: Result<ProcessResult, any Error>) async {
        let probe = RunningAppsProbe.forCurrentMachine(runner: FakeProcessRunner(outcome: outcome), home: "/Users/tester")
        #expect(await probe.affectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]).isEmpty)
    }
}
