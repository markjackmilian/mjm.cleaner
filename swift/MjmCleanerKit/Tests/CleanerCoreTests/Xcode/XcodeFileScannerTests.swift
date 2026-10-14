import Darwin
import Testing
@testable import CleanerCore

struct XcodeFileScannerTests {
    private static let home = "/Users/tester"
    private static let xcode = home + "/Library/Developer/Xcode"

    /// Porting di `FakeSizeProbe`: dimensioni prestabilite per percorso, registro delle misure.
    private struct FakeSizeProbe: XcodeSizeProbing {
        let values: [String: Int64?]
        let measuredPaths = Recorder<String>()

        init(_ values: (String, Int64?)...) {
            var map: [String: Int64?] = [:]
            for (path, bytes) in values { map[path] = .some(bytes) }
            self.values = map
        }

        func measure(_ path: String) async throws -> Int64? {
            measuredPaths.append(path)
            return values[path] ?? nil
        }

        func freeBytes() async throws -> Int64? { 1234 }
    }

    /// Porting di `InaccessibleRootFileSystem`: la root risulta assente a `directoryExists` ed
    /// elencarla lancia accesso negato, come una cartella senza permesso di lettura.
    private final class InaccessibleRootFileSystem: ForwardingFileSystem, @unchecked Sendable {
        private let path: String

        init(_ inner: any FileSystem, path: String) {
            self.path = path
            super.init(inner)
        }

        override func directoryExists(_ path: String) -> Bool {
            path == self.path ? false : super.directoryExists(path)
        }

        override func contentsOfDirectory(_ path: String) throws -> [String] {
            if path == self.path { throw FileSystemError(code: EACCES, path: path) }
            return try super.contentsOfDirectory(path)
        }
    }

    private func create(_ fs: any FileSystem, _ sizes: FakeSizeProbe, links: FakeLinkInspector = FakeLinkInspector()) throws -> XcodeFileScanner {
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home)
        let rules = RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: SystemWallClock())
        return XcodeFileScanner(fileSystem: fs, ruleScanner: rules, pathGuard: pathGuard, links: links, sizeProbe: sizes, homeDirectory: Self.home)
    }

    @Test func derivedDataIsGroupedByProjectFolder() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.xcode + "/DerivedData/App-abc/Build/Products/app", size: 17)
        fs.addFile(Self.xcode + "/DerivedData/Tool-xyz/Index.noindex/store", size: 29)
        fs.addFile(Self.xcode + "/DerivedData/loose-file", text: "ignore")
        let sizes = FakeSizeProbe((Self.xcode + "/DerivedData/App-abc", 100), (Self.xcode + "/DerivedData/Tool-xyz", 200))

        let snapshot = try await create(fs, sizes).scan()

        let candidates = snapshot.candidates.filter { $0.kind == .derivedData }.sorted { $0.name < $1.name }
        #expect(candidates.map(\.name) == ["App-abc", "Tool-xyz"])
        #expect(candidates.map(\.sizeBytes) == [100, 200])
        #expect(snapshot.fileInventory.count == 2)
        for entry in snapshot.fileInventory.values {
            #expect(entry.item.isDirectory)
            #expect(entry.item.path == entry.identity.canonicalPath)
            #expect(entry.identity.creationTime != nil)
            #expect(entry.identity.lastWriteTime != nil)
        }
    }

    @Test func archivesAndUserDataAreNeverCandidates() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.xcode + "/Archives/release.xcarchive/Products/app", size: 50)
        fs.addFile(Self.xcode + "/UserData/Provisioning Profiles/profile", size: 50)

        let snapshot = try await create(fs, FakeSizeProbe()).scan()

        #expect(snapshot.candidates.isEmpty)
        #expect(!snapshot.fileInventory.values.contains { $0.item.path.contains("Archives") })
        #expect(!snapshot.fileInventory.values.contains { $0.item.path.contains("UserData") })
    }

    @Test func absentSupportFolderIsEmpty() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.xcode + "/DerivedData/App/Build/file", size: 1)

        let snapshot = try await create(fs, FakeSizeProbe()).scan()

        #expect(!snapshot.warnings.contains { $0.resourceGroup == .deviceSupport })
        #expect(!snapshot.candidates.contains { $0.kind == .deviceSupport })
    }

    @Test func linkedRootIsRejected() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.xcode + "/DerivedData/App/Build/file", size: 1)

        let snapshot = try await create(fs, FakeSizeProbe(), links: FakeLinkInspector(Self.xcode + "/DerivedData")).scan()

        #expect(!snapshot.candidates.contains { $0.kind == .derivedData })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .derivedData })
    }

    @Test func partialLogicalTraversalBlocksAffectedCandidateAndMarksLogicalSizeUnknown() async throws {
        let mock = InMemoryFileSystem()
        let app = Self.xcode + "/DerivedData/App-abc"
        let unreadable = app + "/Build"
        mock.addFile(unreadable + "/Products/app", size: 17)

        let snapshot = try await create(UnreadableDirectoryFileSystem(mock, unreadablePath: unreadable), FakeSizeProbe((app, 100))).scan()

        let candidates = snapshot.candidates.filter { $0.kind == .derivedData }
        #expect(candidates.count == 1)
        let candidate = try #require(candidates.first)
        #expect(!candidate.canSelect)
        #expect(snapshot.fileInventory[candidate.key]?.identity.logicalSizeBytes == nil)
    }

    @Test func rootHiddenByAccessDeniedExistsCheckProducesWarning() async throws {
        let mock = InMemoryFileSystem()
        mock.addFile(Self.xcode + "/DerivedData/App-abc/Build/app", size: 1)
        let fs = InaccessibleRootFileSystem(mock, path: Self.xcode + "/DerivedData")

        let snapshot = try await create(fs, FakeSizeProbe()).scan()

        #expect(snapshot.warnings.contains { $0.resourceGroup == .derivedData })
    }

    @Test func sharedBackingImageCountedOnce() async throws {
        let backing = Self.home + "/Library/Developer/CoreSimulator/Images/shared.dmg"
        let original = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "runtime:11111111-1111-4111-8111-111111111111", kind: .runtime, name: "iOS 18", path: backing),
            XcodeCandidate(key: "runtime:22222222-2222-4222-8222-222222222222", kind: .runtime, name: "iOS 18 duplicate", path: backing),
        ], warnings: [])
        let fs = InMemoryFileSystem()
        fs.addFile(backing, size: 1)
        let sizes = FakeSizeProbe((backing, 4096))

        let measured = try await create(fs, sizes).measureRuntimeBackingImages(original)

        #expect(measured.candidates.first { XcodeText.hasOrdinalPrefix($0.key, "runtime:111") }?.sizeBytes == 4096)
        #expect(measured.candidates.first { XcodeText.hasOrdinalPrefix($0.key, "runtime:222") }?.sizeBytes == nil)
        #expect(measured.warnings.contains { $0.resourceGroup == .runtime && XcodeText.containsIgnoringCase($0.message, "condivis") })
        #expect(sizes.measuredPaths.values.count == 1)
    }

    // Solo Swift: le righe Device Support portano la piattaforma nella chiave e nel nome.
    @Test func deviceSupportRowsCarryThePlatformInKeyAndName() async throws {
        let fs = InMemoryFileSystem()
        let folder = Self.xcode + "/iOS DeviceSupport/iPhone16,2 18.0 (22A3354)"
        fs.addFile(folder + "/Symbols/dyld", size: 5)

        let snapshot = try await create(fs, FakeSizeProbe((folder, 4096))).scan()

        let candidate = try #require(snapshot.candidates.first)
        #expect(snapshot.candidates.count == 1)
        #expect(candidate.kind == .deviceSupport)
        #expect(candidate.key == "device-support:iOS:" + folder)
        #expect(candidate.name == "iOS: iPhone16,2 18.0 (22A3354)")
        #expect(candidate.sizeBytes == 4096)
        #expect(snapshot.fileInventory[candidate.key]?.item.declaredRoot == Self.xcode + "/iOS DeviceSupport")
        #expect(snapshot.fileInventory[candidate.key]?.identity.logicalSizeBytes == 5)
    }
}
