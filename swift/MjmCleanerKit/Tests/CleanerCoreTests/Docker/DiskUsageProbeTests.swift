import Testing
@testable import CleanerCore

struct DiskUsageProbeTests {
    private static let rawPath = "/Users/tester/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"

    private struct DuRunner: ProcessRunning {
        let standardOutput: String
        var exitCode: Int32 = 0
        let calls = Recorder<[String]>()

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            calls.append([executable] + arguments)
            return ProcessResult(exitCode: exitCode, standardOutput: standardOutput, standardError: "", timedOut: false)
        }
    }

    @Test(arguments: [
        ("8677192\t/Users/tester/Docker.raw\n", Int64(8_677_192) * 1024),
        ("0\t/x\n", 0),
    ])
    func parsesTheKilobytesPrintedByDu(output: String, expected: Int64) {
        #expect(DiskUsageProbe.parseDuKilobytes(output) == expected)
    }

    @Test func unreadableDuOutputIsUnknown() {
        #expect(DiskUsageProbe.parseDuKilobytes("du: Docker.raw: Operation not permitted") == nil)
    }

    @Test func defaultPathIsTheDockerDesktopDiskOnMacOS() {
        #expect(DiskUsageProbe.defaultPath("/Users/tester") == Self.rawPath)
    }

    @Test func sparseFileReportsBothAllocatedAndApparentSize() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 4096)
        let du = DuRunner(standardOutput: "8\t" + Self.rawPath + "\n")

        let usage = try await DiskUsageProbe(runner: du, fileSystem: fs, diskImagePath: Self.rawPath).measure()

        #expect(usage.exists)
        #expect(usage.allocatedBytes == Int64(8 * 1024))
        #expect(usage.apparentBytes == 4096)
        #expect(du.calls.values == [["du", "-k", Self.rawPath]])
    }

    @Test func missingDiskImageIsReportedWithoutRunningDu() async throws {
        let du = DuRunner(standardOutput: "")

        let usage = try await DiskUsageProbe(runner: du, fileSystem: InMemoryFileSystem(), diskImagePath: Self.rawPath).measure()

        #expect(!usage.exists)
        #expect(usage.allocatedBytes == nil)
        #expect(du.calls.values.isEmpty)
    }

    @Test func failingDuLeavesOnlyTheApparentSize() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 10)

        let usage = try await DiskUsageProbe(runner: DuRunner(standardOutput: "", exitCode: 1), fileSystem: fs, diskImagePath: Self.rawPath).measure()

        #expect(usage.allocatedBytes == nil)
        #expect(usage.apparentBytes == 10)
    }
}
