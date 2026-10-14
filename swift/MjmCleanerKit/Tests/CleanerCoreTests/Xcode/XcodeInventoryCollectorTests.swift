import Synchronization
import Testing
@testable import CleanerCore

struct XcodeInventoryCollectorTests {
    private struct FakeCli: XcodeCliInvoking {
        let snapshot: XcodeSnapshot

        func readInventory() async throws -> XcodeSnapshot { snapshot }
        func deleteDevice(_ uuid: String) async throws -> ProcessResult { throw XcodeOperationError("non supportato") }
        func deleteRuntime(_ uuid: String) async throws -> ProcessResult { throw XcodeOperationError("non supportato") }
    }

    private final class FakeFileScanner: XcodeFileScanning {
        private let files: XcodeSnapshot
        private let runtimeBytes: Int64
        private let calls = Mutex<(scan: Bool, measure: Bool)>((false, false))

        init(_ files: XcodeSnapshot, runtimeBytes: Int64) {
            self.files = files
            self.runtimeBytes = runtimeBytes
        }

        var scanCalled: Bool { calls.withLock { $0.scan } }
        var measureCalled: Bool { calls.withLock { $0.measure } }

        func scan() async throws -> XcodeSnapshot {
            calls.withLock { $0.scan = true }
            return files
        }

        func measureRuntimeBackingImages(_ snapshot: XcodeSnapshot) async throws -> XcodeSnapshot {
            calls.withLock { $0.measure = true }
            var measured = snapshot
            measured.candidates = snapshot.candidates.map { candidate in
                var copy = candidate
                if candidate.kind == .runtime { copy.sizeBytes = runtimeBytes }
                return copy
            }
            return measured
        }
    }

    @Test func emptyInventoryIsSuccessful() async throws {
        let snapshot = try await XcodeInventoryCollector(cli: FakeCli(snapshot: .empty)).collect()

        #expect(snapshot.candidates.isEmpty)
        #expect(snapshot.warnings.isEmpty)
    }

    @Test func collectorAddsFileRowsAndMeasuresRuntimeBackingSize() async throws {
        let cliSnapshot = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "runtime:11111111-1111-4111-8111-111111111111", kind: .runtime, name: "iOS 18", path: "/backing/AssetData"),
        ], warnings: [])
        let fileSnapshot = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "derived-data:/Users/tester/Library/Developer/Xcode/DerivedData/App", kind: .derivedData, name: "App"),
        ], warnings: [])
        let scanner = FakeFileScanner(fileSnapshot, runtimeBytes: 4096)

        let collected = try await XcodeInventoryCollector(cli: FakeCli(snapshot: cliSnapshot), fileScanner: scanner).collect()

        #expect(scanner.scanCalled)
        #expect(scanner.measureCalled)
        #expect(collected.candidates.first { $0.kind == .runtime }?.sizeBytes == 4096)
        #expect(collected.candidates.contains { $0.kind == .derivedData })
    }
}
