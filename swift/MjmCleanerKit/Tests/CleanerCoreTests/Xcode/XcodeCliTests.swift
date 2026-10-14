import Darwin
import Testing
@testable import CleanerCore

struct XcodeCliTests {
    /// Porting di `FakeRunner`: registra argomenti, timeout, eseguibile e ambiente di ogni avvio.
    private struct FakeRunner: ProcessRunning {
        struct Call: Sendable {
            let executable: String
            let arguments: [String]
            let timeout: Duration
            let environment: [String: String]?
        }

        let calls = Recorder<Call>()
        let respond: @Sendable ([String]) throws -> ProcessResult

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            calls.append(Call(executable: executable, arguments: arguments, timeout: timeout, environment: environment))
            return try respond(arguments)
        }
    }

    private static func result(_ exitCode: Int32, _ standardOutput: String, _ standardError: String, timedOut: Bool = false) -> ProcessResult {
        ProcessResult(exitCode: exitCode, standardOutput: standardOutput, standardError: standardError, timedOut: timedOut)
    }

    @Test func deleteUsesOnlyValidatedUuid() async throws {
        let runner = FakeRunner { _ in Self.result(0, "ok", "") }
        let cli = XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun")
        let uuid = "11111111-1111-4111-8111-111111111111"

        _ = try await cli.deleteDevice(uuid)
        _ = try await cli.deleteRuntime("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")

        let calls = runner.calls.values
        #expect(calls.map(\.arguments) == [
            ["simctl", "delete", uuid],
            ["simctl", "runtime", "delete", "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"],
        ])
        #expect(calls.allSatisfy { $0.timeout == .seconds(300) })
    }

    @Test(arguments: ["all", "unavailable", "not-a-uuid", "--unusable"])
    func invalidDeleteIdentifiersNeverLaunchAProcess(id: String) async {
        let runner = FakeRunner { _ in Self.result(0, "", "") }
        let cli = XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun")

        await #expect(throws: XcodeArgumentError.self) { try await cli.deleteRuntime(id) }
        await #expect(throws: XcodeArgumentError.self) { try await cli.deleteDevice(id) }

        #expect(runner.calls.values.isEmpty)
    }

    @Test func runtimeDeleteUnsupportedIsReported() async throws {
        let runner = FakeRunner { arguments in
            arguments == ["simctl", "runtime"] ? Self.result(1, "", "unknown operation") : Self.result(0, "{}", "")
        }
        let cli = XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun")

        let snapshot = try await cli.readInventory()

        #expect(snapshot.warnings.contains { $0.resourceGroup == .runtime && XcodeText.containsIgnoringCase($0.message, "Settings") })
        #expect(snapshot.candidates.isEmpty)
    }

    @Test func inventoryCommandsUseThirtySecondTimeoutAndSeparateArguments() async throws {
        let runner = FakeRunner { _ in Self.result(0, "{}", "") }
        let cli = XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun")

        _ = try await cli.readInventory()

        let calls = runner.calls.values
        #expect(calls.contains { $0.arguments == ["simctl", "list", "--json"] })
        #expect(calls.contains { $0.arguments == ["simctl", "runtime", "list", "--json"] })
        #expect(calls.allSatisfy { $0.timeout == .seconds(30) })
    }

    @Test func runtimeInventoryIsStillReadWhenSimulatorInventoryCommandFails() async throws {
        let runner = FakeRunner { arguments in
            if arguments == ["simctl", "list", "--json"] { return Self.result(1, "", "simulator service unavailable") }
            if arguments == ["simctl", "runtime"] { return Self.result(0, "delete (<identifier>)", "") }
            return Self.result(0, "{}", "")
        }

        let snapshot = try await XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun").readInventory()

        #expect(snapshot.warnings.contains { $0.resourceGroup == .device })
        #expect(runner.calls.values.contains { $0.arguments == ["simctl", "runtime", "list", "--json"] })
    }

    @Test func runtimeDeleteIsSupportedWhenHelpPrintsSyntaxWithUsageExitCode() async throws {
        let simctlJson = try XcodeFixtures.text("simctl-list.json")
        let runtimeJson = try XcodeFixtures.text("runtime-list.json")
        let runner = FakeRunner { arguments in
            if arguments == ["simctl", "list", "--json"] { return Self.result(0, simctlJson, "") }
            if arguments == ["simctl", "runtime"] { return Self.result(117, "", "delete (<identifier>|--unusable)") }
            return Self.result(0, runtimeJson, "")
        }

        let snapshot = try await XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun").readInventory()

        let runtimes = snapshot.candidates.filter { $0.kind == .runtime }
        #expect(runtimes.count == 1)
        #expect(runtimes.first?.canSelect == true)
    }

    // Solo Swift: la scansione che sostituisce la regex `(?m)^\s*delete\s+\(<identifier>` dà gli
    // stessi esiti misurati su .NET 10.
    @Test(arguments: [
        ("delete (<identifier>)", true),
        ("  delete  (<identifier>|--unusable)", true),
        ("x\n delete\n(<identifier>", true),
        ("x\r delete (<identifier>", false),
        ("xdelete (<identifier>", false),
        ("\u{2028}delete (<identifier>", true),
        ("\u{A0}delete\u{A0}(<identifier>", true),
        ("\u{85}delete (<identifier>", true),
        ("Delete (<identifier>", false),
        ("delete(<identifier>", false),
    ])
    func runtimeDeleteSyntaxIsRecognizedLikeTheDotNetRegex(helpText: String, expected: Bool) {
        #expect(XcodeCli.listsRuntimeDelete(helpText) == expected)
    }

    // Solo Swift: xcrun si avvia per percorso assoluto, con la sua cartella in testa al PATH.
    @Test func commandsRunXcrunByAbsolutePathWithItsDirectoryFirstInPath() async throws {
        let runner = FakeRunner { _ in Self.result(0, "{}", "") }

        _ = try await XcodeCli(runner: runner, binaryPath: XcodeCli.defaultBinaryPath).readInventory()

        let calls = runner.calls.values
        #expect(calls.count == 3)
        #expect(calls.allSatisfy { $0.executable == "/usr/bin/xcrun" })
        #expect(calls.allSatisfy {
            XcodeText.hasOrdinalPrefix($0.environment?["PATH"] ?? "", "/usr/bin:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin")
        })
    }

    // Solo Swift: xcrun assente o non avviabile produce gli avvisi di oggi (spec §8.1) e nessun
    // candidato; l'eseguibile si cerca solo in /usr/bin/xcrun, come nella composizione C#.
    @Test func missingOrUnlaunchableXcrunIsReportedAsUnavailable() async throws {
        let unlaunchable = FakeRunner { _ in throw ProcessLaunchError(executable: "/usr/bin/xcrun", code: ENOENT) }
        let fs = InMemoryFileSystem()

        let missing = try await XcodeCli(runner: unlaunchable, binaryPath: XcodeCli.locateBinary(fs)).readInventory()
        let broken = try await XcodeCli(runner: unlaunchable, binaryPath: "/usr/bin/xcrun").readInventory()

        for snapshot in [missing, broken] {
            #expect(snapshot.candidates.isEmpty)
            #expect(snapshot.warnings.filter { $0.message == "Xcode command line tools non trovati." }.count == 3)
        }
        fs.addFile("/usr/bin/xcrun", size: 1)
        #expect(XcodeCli.locateBinary(fs) == "/usr/bin/xcrun")
    }
}
