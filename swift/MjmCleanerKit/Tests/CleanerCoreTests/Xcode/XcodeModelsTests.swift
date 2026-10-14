import Foundation
import Testing
@testable import CleanerCore

/// Test solo Swift: le proprietà dei modelli che in C# derivavano da record e `IReadOnlyDictionary`.
struct XcodeModelsTests {
    private func entry(_ path: String) -> XcodeFileEntry {
        XcodeFileEntry(
            item: ScanItem(path: path, sizeBytes: 1, isDirectory: true, declaredRoot: "/r"),
            identity: XcodeFileIdentity(canonicalPath: path, isDirectory: true, creationTime: Date(timeIntervalSince1970: 0),
                                        lastWriteTime: Date(timeIntervalSince1970: 0), logicalSizeBytes: 1))
    }

    @Test func fileInventoryComparesKeysOrdinallyAndKeepsInsertionOrder() {
        let nfc = "derived-data:/r/Caf\u{E9}"
        let nfd = "derived-data:/r/Cafe\u{301}"
        let inventory = XcodeFileInventory([(nfd, entry("/r/b")), (nfc, entry("/r/a")), (nfd, entry("/r/c"))])

        #expect(inventory.keys == [nfd, nfc])
        #expect(inventory.count == 2)
        #expect(inventory[nfd] == entry("/r/b"))
        #expect(inventory[nfc] == entry("/r/a"))
        #expect(!inventory.contains("derived-data:/r/caf\u{E9}"))
        #expect(inventory.values == [entry("/r/b"), entry("/r/a")])
    }

    @Test func warningsDefaultToCompletenessFailureAndCandidatesDeriveTheirState() {
        #expect(XcodeInventoryWarning(resourceGroup: .device, message: "x").kind == .completenessFailure)
        #expect(XcodeInventoryWarning.advisory(.runtime, "y").kind == .advisory)

        var candidate = XcodeCandidate(key: "k", kind: .runtime, name: "iOS 18")
        #expect(candidate.canSelect)
        #expect(candidate.dependentDeviceKeys.isEmpty)
        candidate.blockReason = "bloccato"
        candidate.dependencies = ["d"]
        #expect(!candidate.canSelect)
        #expect(candidate.dependentDeviceKeys == ["d"])
    }
}
