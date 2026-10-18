import Darwin
import Foundation
import Testing
@testable import CleanerCore

struct XcodeSizeProbeTests {
    private struct ThrowingRunner: ProcessRunning {
        let error: any Error

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            throw error
        }
    }

    private struct ReturningRunner: ProcessRunning {
        let result: ProcessResult
        let calls = Recorder<[String]>()

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            calls.append([executable] + arguments)
            return result
        }
    }

    private static func result(_ exitCode: Int32, _ standardOutput: String, _ standardError: String) -> ProcessResult {
        ProcessResult(exitCode: exitCode, standardOutput: standardOutput, standardError: standardError, timedOut: false)
    }

    @Test func accessDeniedSizeIsUnknown() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let directory = try tmp.directory("cache")
        let probe = XcodeSizeProbe(
            fileSystem: LocalFileSystem(), runner: ThrowingRunner(error: FileSystemError(code: EACCES, path: "du")),
            links: FileSystemLinkInspector(), homeDirectory: tmp.path)

        #expect(try await probe.measure(directory) == nil)
    }

    @Test func partialDuMeasurementIsUnknown() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let probe = XcodeSizeProbe(
            fileSystem: LocalFileSystem(), runner: ReturningRunner(result: Self.result(1, "12\tcache", "permission denied")),
            links: FileSystemLinkInspector(), homeDirectory: tmp.path)

        #expect(try await probe.measure(tmp.path) == nil)
    }

    @Test func freeBytesComeFromTheVolumeContainingHome() async throws {
        let probe = XcodeSizeProbe(
            fileSystem: LocalFileSystem(), runner: ReturningRunner(result: Self.result(0, "1\tunused", "")),
            links: FileSystemLinkInspector(), homeDirectory: NSHomeDirectory())

        let free = try await probe.freeBytes()

        #expect(free != nil)
        #expect((free ?? -1) >= 0)
    }

    // Solo Swift: le regole di lettura dell'output di du (una sola riga, solo cifre ASCII nel
    // primo campo, nessun errore) e il comando esatto.
    @Test(arguments: [
        (Self.result(0, "12\t/x\n", ""), 12_288 as Int64?),
        (Self.result(0, "  7 /x", ""), 7_168 as Int64?),
        (Self.result(0, "12\t/x\n3\t/y", ""), nil),
        (Self.result(0, "+12\t/x", ""), nil),
        (Self.result(0, "\u{0661}\t/x", ""), nil),
        (Self.result(0, "9007199254740992\t/x", ""), nil),
        (Self.result(0, "12\t/x", "du: x: Permission denied"), nil),
        (Self.result(1, "12\t/x", ""), nil),
        (ProcessResult(exitCode: 0, standardOutput: "12\t/x", standardError: "", timedOut: true), nil),
    ])
    func measureParsesOnlyASingleCleanDuRow(output: ProcessResult, expected: Int64?) async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let runner = ReturningRunner(result: output)
        let probe = XcodeSizeProbe(fileSystem: LocalFileSystem(), runner: runner, links: FileSystemLinkInspector(), homeDirectory: tmp.path)

        #expect(try await probe.measure(tmp.path) == expected)
        #expect(runner.calls.values == [["du", "-k", "-s", "-P", tmp.path]])
    }

    // Solo Swift: percorsi relativi, collegamenti e percorsi assenti non avviano du.
    @Test func measureRefusesLinksRelativeAndMissingPathsWithoutLaunchingDu() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let target = try tmp.directory("target")
        let link = try tmp.symlink("link", to: target)
        let runner = ReturningRunner(result: Self.result(0, "1\t/x", ""))
        let probe = XcodeSizeProbe(fileSystem: LocalFileSystem(), runner: runner, links: FileSystemLinkInspector(), homeDirectory: tmp.path)

        #expect(try await probe.measure("relativo/cartella") == nil)
        #expect(try await probe.measure(link) == nil)
        #expect(try await probe.measure(tmp.path + "/assente") == nil)
        #expect(runner.calls.values.isEmpty)
    }

    // Solo Swift: un volume illeggibile dà spazio sconosciuto, non un errore.
    @Test func freeBytesAreUnknownWhenTheVolumeCannotBeRead() async throws {
        let probe = XcodeSizeProbe(
            fileSystem: InMemoryFileSystem(), runner: ReturningRunner(result: Self.result(0, "", "")),
            links: FakeLinkInspector(), homeDirectory: "/Users/tester")

        #expect(try await probe.freeBytes() == nil)
    }
}
