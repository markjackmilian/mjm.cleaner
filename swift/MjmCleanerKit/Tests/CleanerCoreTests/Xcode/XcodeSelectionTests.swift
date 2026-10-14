import Foundation
import Testing
@testable import CleanerCore

struct XcodeSelectionTests {
    private static let deviceKey = "11111111-1111-4111-8111-111111111111"
    private static let runtimeKey = "runtime:22222222-2222-4222-8222-222222222222"

    private func createSnapshot(_ candidates: XcodeCandidate...) throws -> XcodeSnapshot {
        try XcodeClassifier.classify(XcodeSnapshot(candidates: candidates, warnings: []), xcodeRunning: false)
    }

    private func device() -> XcodeCandidate {
        XcodeCandidate(key: Self.deviceKey, kind: .device, name: "iPhone 16", cliId: Self.deviceKey, state: "Shutdown", sizeBytes: 10)
    }

    private func runtime(_ dependencies: [String]?) -> XcodeCandidate {
        XcodeCandidate(key: Self.runtimeKey, kind: .runtime, name: "iOS 18", cliId: "22222222-2222-4222-8222-222222222222", sizeBytes: 20, dependencies: dependencies)
    }

    /// `XcodeFileIdentity(path, true, time, time, size)`: `nil` sta per `default(DateTime)`.
    private func entry(_ itemPath: String, identityPath: String, time: Date?, logicalSize: Int64?) -> XcodeFileEntry {
        XcodeFileEntry(
            item: ScanItem(path: itemPath, sizeBytes: 3, isDirectory: true, declaredRoot: "/"),
            identity: XcodeFileIdentity(canonicalPath: identityPath, isDirectory: true, creationTime: time, lastWriteTime: time, logicalSizeBytes: logicalSize))
    }

    @Test func unknownKeyIsRejected() throws {
        let snapshot = try createSnapshot(device(), runtime([Self.deviceKey]))
        #expect(throws: XcodeArgumentError.self) { try XcodeSelection.preview(snapshot, selectedKeys: ["unknown"]) }
    }

    @Test func duplicateNormalizedUuidSelectionsCollapse() throws {
        let snapshot = try createSnapshot(device())
        let preview = try XcodeSelection.preview(snapshot, selectedKeys: [Self.deviceKey, Self.deviceKey.uppercased()])
        #expect(preview.selectedCandidates.count == 1)
    }

    @Test func directSelectionOfBlockedRowIsRejected() {
        var blocked = device()
        blocked.state = "Booted"
        let snapshot = XcodeSnapshot(candidates: [blocked], warnings: [])
        #expect(throws: XcodeArgumentError.self) { try XcodeSelection.preview(snapshot, selectedKeys: [Self.deviceKey]) }
    }

    @Test func selectedFileWithoutGuardedInventoryIsRejected() throws {
        let file = XcodeCandidate(key: "derived-data:/one", kind: .derivedData, name: "One", path: "/one", sizeBytes: 3)
        let snapshot = try createSnapshot(file)
        #expect(throws: XcodeArgumentError.self) { try XcodeSelection.preview(snapshot, selectedKeys: [file.key]) }
    }

    @Test func selectedFileWithIncompleteGuardedInventoryIsRejected() throws {
        let file = XcodeCandidate(key: "derived-data:/one", kind: .derivedData, name: "One", path: "/one", sizeBytes: 3)
        var snapshot = try createSnapshot(file)
        snapshot.fileInventory = XcodeFileInventory([(file.key, entry("/elsewhere", identityPath: "/one", time: nil, logicalSize: 3))])
        #expect(throws: XcodeArgumentError.self) { try XcodeSelection.preview(snapshot, selectedKeys: [file.key]) }
    }

    @Test func retainedDependenciesRequireAcknowledgement() throws {
        let preview = try XcodeSelection.preview(try createSnapshot(device(), runtime([Self.deviceKey])), selectedKeys: [Self.runtimeKey])
        #expect(preview.retainedDependentDevices.contains { $0.key == Self.deviceKey })
        #expect(throws: XcodeOperationError.self) { try XcodeSelection.confirm(preview, acknowledgeDependencies: false) }
        #expect(try XcodeSelection.confirm(preview, acknowledgeDependencies: true).candidates.count == 1)
    }

    @Test func confirmDoesNotSelectDependentDevices() throws {
        let preview = try XcodeSelection.preview(try createSnapshot(device(), runtime([Self.deviceKey])), selectedKeys: [Self.runtimeKey])
        let plan = try XcodeSelection.confirm(preview, acknowledgeDependencies: true)
        #expect(!plan.candidates.contains { $0.key == Self.deviceKey })
        #expect(plan.candidates.count == 1)
        #expect(plan.candidates.first?.key == Self.runtimeKey)
    }

    @Test func unknownSizesRemainVisible() throws {
        let unknown = XcodeCandidate(key: "derived-data:/unknown", kind: .derivedData, name: "Unknown", path: "/unknown", sizeBytes: nil)
        var snapshot = try createSnapshot(unknown)
        snapshot.fileInventory = XcodeFileInventory([(unknown.key, entry("/unknown", identityPath: "/unknown", time: Date(timeIntervalSince1970: 0), logicalSize: nil))])

        let preview = try XcodeSelection.preview(snapshot, selectedKeys: [unknown.key])

        #expect(preview.unknownSizeCount == 1)
        #expect(preview.estimatedBytes == 0)
        #expect(preview.selectedCandidates.count == 1)
        #expect(preview.selectedCandidates.first?.sizeBytes == nil)
    }

    // In C# la lista dei candidati del piano era di sola lettura (NotSupportedException su Add).
    // In Swift è un valore: si verifica che modificarne una copia non tocchi il piano.
    @Test func confirmationCopiesCandidatesAndGuardedInventory() throws {
        let file = XcodeCandidate(key: "derived-data:/one", kind: .derivedData, name: "One", path: "/one", sizeBytes: 3)
        let guarded = entry("/one", identityPath: "/one", time: Date(timeIntervalSince1970: 0), logicalSize: 3)
        var snapshot = try createSnapshot(file)
        snapshot.fileInventory = XcodeFileInventory([(file.key, guarded)])

        let preview = try XcodeSelection.preview(snapshot, selectedKeys: [file.key])
        let plan = try XcodeSelection.confirm(preview, acknowledgeDependencies: true)

        #expect(plan.fileInventory[file.key] == guarded)
        var candidates = plan.candidates
        candidates.append(file)
        #expect(plan.candidates.count == 1)
    }
}
