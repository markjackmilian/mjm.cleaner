import Darwin
import Foundation
import Synchronization
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
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home)
        let rules = RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: SystemWallClock())
        return XcodeFileScanner(fileSystem: fs, ruleScanner: rules, pathGuard: pathGuard, links: links, sizeProbe: sizes, homeDirectory: Self.home)
    }

    // MARK: - Doppi della guardia e dell'identità (solo Swift)

    /// Guard reale con verdetti sostituiti per percorso: li usa solo `XcodeFileScanner`, mentre
    /// `RuleScanner` resta sul guard reale e continua a produrre l'elemento.
    private struct OverridingPathGuard: PathGuarding {
        let inner: any PathGuarding
        let verdicts: [String: GuardVerdict]

        func validateRoot(_ declaredRoot: String) -> GuardVerdict {
            inner.validateRoot(declaredRoot)
        }

        func validate(_ candidatePath: String, declaredRoot: String) -> GuardVerdict {
            verdicts[candidatePath] ?? inner.validate(candidatePath, declaredRoot: declaredRoot)
        }

        func pruneReason(_ candidatePath: String) -> String? {
            inner.pruneReason(candidatePath)
        }
    }

    /// Cartelle che `RuleScanner` ha già elencato: il punto da cui i doppi cambiano comportamento.
    private final class ListingLog: Sendable {
        private let listed = Mutex<Set<String>>([])

        func record(_ path: String) {
            listed.withLock { _ = $0.insert(path) }
        }

        func contains(_ path: String) -> Bool {
            listed.withLock { $0.contains(path) }
        }
    }

    /// Registra le cartelle elencate. Con `replaceAfterListing` la cartella diventa un file dopo
    /// l'elenco: `directoryExists` la vede assente, mentre `itemInfo` la legge ancora.
    private final class ListingFileSystem: ForwardingFileSystem, @unchecked Sendable {
        private let folder: String
        private let log: ListingLog
        private let replaceAfterListing: Bool

        init(_ inner: any FileSystem, folder: String, log: ListingLog, replaceAfterListing: Bool) {
            self.folder = folder
            self.log = log
            self.replaceAfterListing = replaceAfterListing
            super.init(inner)
        }

        override func contentsOfDirectory(_ path: String) throws -> [String] {
            let entries = try super.contentsOfDirectory(path)
            log.record(path)
            return entries
        }

        override func directoryExists(_ path: String) -> Bool {
            if replaceAfterListing, path == folder, log.contains(path) { return false }
            return super.directoryExists(path)
        }
    }

    /// Il collegamento compare solo dopo l'elenco di `RuleScanner`: prima la cartella è reale.
    private struct LinkAfterListing: LinkInspecting {
        let folder: String
        let log: ListingLog

        func isSymbolicLink(_ path: String) -> Bool {
            path == folder && log.contains(path)
        }

        func resolveLinkTarget(_ path: String) -> String? {
            nil
        }
    }

    /// Date prestabilite per percorso: `InMemoryFileSystem` assegna alle cartelle la data della
    /// propria creazione, quindi la root e la cartella non si distinguerebbero.
    private final class DatedFileSystem: ForwardingFileSystem, @unchecked Sendable {
        private let dates: [String: (creation: Date, lastWrite: Date)]

        init(_ inner: any FileSystem, dates: [String: (creation: Date, lastWrite: Date)]) {
            self.dates = dates
            super.init(inner)
        }

        override func itemInfo(_ path: String) throws -> FileItemInfo {
            let info = try super.itemInfo(path)
            guard let dated = dates[path] else { return info }
            return FileItemInfo(kind: info.kind, size: info.size, lastWrite: dated.lastWrite, lastAccess: info.lastAccess, creation: dated.creation)
        }
    }

    /// Come `create`, ma con il guard dello scanner sostituito per percorso e il collegamento scelto.
    private func makeScanner(
        _ fs: any FileSystem,
        _ sizes: FakeSizeProbe,
        links: any LinkInspecting = FakeLinkInspector(),
        verdicts: [String: GuardVerdict] = [:]
    ) throws -> XcodeFileScanner {
        let real = try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home)
        let rules = RuleScanner(fileSystem: fs, pathGuard: real, links: links, clock: SystemWallClock())
        return XcodeFileScanner(
            fileSystem: fs,
            ruleScanner: rules,
            pathGuard: OverridingPathGuard(inner: real, verdicts: verdicts),
            links: links,
            sizeProbe: sizes,
            homeDirectory: Self.home)
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
            let info = try fs.itemInfo(entry.identity.canonicalPath)
            #expect(entry.identity.creationTime == info.creation)
            #expect(entry.identity.lastWriteTime == info.lastWrite)
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

    // MARK: - Guardia e identità dell'elemento (solo Swift)

    @Test func canonicalPathFromTheGuardReachesCandidateInventoryAndMeasurement() async throws {
        let fs = InMemoryFileSystem()
        let folder = Self.xcode + "/DerivedData/App-abc"
        let canonical = Self.home + "/Library/Developer/Xcode/Canonical/App-abc"
        fs.addFile(folder + "/Build/app", size: 17)
        fs.addFile(canonical + "/Build/app", size: 9)
        let sizes = FakeSizeProbe((canonical, 555))

        let snapshot = try await makeScanner(fs, sizes, verdicts: [folder: .allow(canonical)]).scan()

        let candidates = snapshot.candidates.filter { $0.kind == .derivedData }
        #expect(candidates.count == 1)
        let candidate = try #require(candidates.first)
        #expect(candidate.key == "derived-data:" + canonical)
        #expect(candidate.path == canonical)
        #expect(candidate.sizeBytes == 555)
        #expect(candidate.canSelect)
        let entry = try #require(snapshot.fileInventory[candidate.key])
        #expect(entry.item.path == canonical)
        #expect(entry.identity.canonicalPath == canonical)
        #expect(sizes.measuredPaths.values == [canonical])
    }

    @Test func folderRefusedByTheScannerGuardIsAbsentFromCandidatesAndInventory() async throws {
        let fs = InMemoryFileSystem()
        let refused = Self.xcode + "/DerivedData/App-abc"
        let kept = Self.xcode + "/DerivedData/Tool-xyz"
        fs.addFile(refused + "/Build/app", size: 17)
        fs.addFile(kept + "/Index.noindex/store", size: 29)

        let snapshot = try await makeScanner(fs, FakeSizeProbe((kept, 200)), verdicts: [refused: .deny("radice negata dal test")]).scan()

        #expect(snapshot.candidates.map(\.name) == ["Tool-xyz"])
        #expect(snapshot.fileInventory.keys == ["derived-data:" + kept])
        #expect(snapshot.warnings.contains { XcodeText.containsIgnoringCase($0.message, "App-abc") })
    }

    @Test func folderLinkedAfterTheListingIsSkippedBeforeItsMetadataIsRead() async throws {
        let fs = InMemoryFileSystem()
        let folder = Self.xcode + "/DerivedData/App-abc"
        fs.addFile(folder + "/Build/app", size: 17)
        let log = ListingLog()
        let listing = ListingFileSystem(fs, folder: folder, log: log, replaceAfterListing: false)

        let snapshot = try await makeScanner(listing, FakeSizeProbe((folder, 100)), links: LinkAfterListing(folder: folder, log: log)).scan()

        #expect(log.contains(folder))
        #expect(!snapshot.candidates.contains { $0.kind == .derivedData })
        #expect(snapshot.fileInventory.count == 0)
        #expect(snapshot.warnings.contains { XcodeText.containsIgnoringCase($0.message, "App-abc") })
    }

    @Test func folderReplacedByAFileAfterTheListingIsSkipped() async throws {
        let fs = InMemoryFileSystem()
        let folder = Self.xcode + "/DerivedData/App-abc"
        fs.addFile(folder + "/Build/app", size: 17)
        let log = ListingLog()
        let listing = ListingFileSystem(fs, folder: folder, log: log, replaceAfterListing: true)

        let snapshot = try await makeScanner(listing, FakeSizeProbe((folder, 100))).scan()

        #expect(log.contains(folder))
        #expect(!snapshot.candidates.contains { $0.kind == .derivedData })
        #expect(snapshot.fileInventory.count == 0)
        #expect(snapshot.warnings.contains { XcodeText.containsIgnoringCase($0.message, "App-abc") })
    }

    @Test func identityDatesComeFromTheFolderItselfNotFromItsRoot() async throws {
        let fs = InMemoryFileSystem()
        let root = Self.xcode + "/DerivedData"
        let folder = root + "/App-abc"
        fs.addFile(folder + "/Build/app", size: 17)
        let dated = DatedFileSystem(fs, dates: [
            root: (creation: utc(2001, 1, 1), lastWrite: utc(2001, 2, 2)),
            folder: (creation: utc(2003, 3, 3), lastWrite: utc(2003, 4, 4)),
        ])

        let snapshot = try await makeScanner(dated, FakeSizeProbe()).scan()

        let rootInfo = try dated.itemInfo(root)
        let folderInfo = try dated.itemInfo(folder)
        #expect(rootInfo.creation != folderInfo.creation)
        #expect(rootInfo.lastWrite != folderInfo.lastWrite)
        let entry = try #require(snapshot.fileInventory["derived-data:" + folder])
        #expect(entry.identity.isDirectory)
        #expect(entry.identity.creationTime == folderInfo.creation)
        #expect(entry.identity.lastWriteTime == folderInfo.lastWrite)
    }

    @Test func runtimeImageIsMeasuredAtItsCanonicalPath() async throws {
        let backing = Self.home + "/Library/Developer/CoreSimulator/Images/shared.dmg"
        let canonical = Self.home + "/Library/Developer/CoreSimulator/Images/canonical.dmg"
        let sizes = FakeSizeProbe((canonical, 8192))
        let original = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "runtime:11111111-1111-4111-8111-111111111111", kind: .runtime, name: "iOS 18", path: backing),
        ], warnings: [])

        let measured = try await makeScanner(InMemoryFileSystem(), sizes, verdicts: [backing: .allow(canonical)])
            .measureRuntimeBackingImages(original)

        let candidate = try #require(measured.candidates.first)
        #expect(candidate.path == canonical)
        #expect(candidate.sizeBytes == 8192)
        #expect(measured.warnings.isEmpty)
        #expect(sizes.measuredPaths.values == [canonical])
    }

    @Test func runtimeImageThroughASymlinkIsNotMeasured() async throws {
        let backing = Self.home + "/Library/Developer/CoreSimulator/Images/shared.dmg"
        let sizes = FakeSizeProbe((backing, 4096))
        let original = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "runtime:11111111-1111-4111-8111-111111111111", kind: .runtime, name: "iOS 18", path: backing),
        ], warnings: [])

        let measured = try await makeScanner(InMemoryFileSystem(), sizes, links: FakeLinkInspector(backing))
            .measureRuntimeBackingImages(original)

        #expect(measured.candidates.first?.sizeBytes == nil)
        #expect(measured.warnings.contains { $0.kind == .advisory && $0.resourceGroup == .runtime && XcodeText.containsIgnoringCase($0.message, "controlli di sicurezza") })
        #expect(sizes.measuredPaths.values.isEmpty)
    }

    @Test func runtimeImagesRefusedByTheGuardAreNotMeasured() async throws {
        let homeChild = Self.home + "/shared.dmg"
        let deniedTree = Self.home + "/.ssh/images/shared.dmg"
        let sizes = FakeSizeProbe((homeChild, 1), (deniedTree, 2))
        let original = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "runtime:11111111-1111-4111-8111-111111111111", kind: .runtime, name: "figlio della home", path: homeChild),
            XcodeCandidate(key: "runtime:22222222-2222-4222-8222-222222222222", kind: .runtime, name: "albero negato", path: deniedTree),
        ], warnings: [])

        let measured = try await makeScanner(InMemoryFileSystem(), sizes).measureRuntimeBackingImages(original)

        #expect(measured.candidates.allSatisfy { $0.sizeBytes == nil })
        #expect(measured.warnings.filter { $0.kind == .advisory && XcodeText.containsIgnoringCase($0.message, "controlli di sicurezza") }.count == 2)
        #expect(sizes.measuredPaths.values.isEmpty)
    }

    @Test func runtimeImageInASymlinkedDeniedRootIsNotMeasured() async throws {
        let root = Self.home + "/Library/Developer/CoreSimulator/Images"
        let backing = root + "/shared.dmg"
        let links = FakeLinkInspector(targets: [root: Self.home + "/.ssh/images"])
        let sizes = FakeSizeProbe((backing, 4096))
        let original = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "runtime:11111111-1111-4111-8111-111111111111", kind: .runtime, name: "iOS 18", path: backing),
        ], warnings: [])

        let measured = try await makeScanner(InMemoryFileSystem(), sizes, links: links).measureRuntimeBackingImages(original)

        #expect(measured.candidates.first?.sizeBytes == nil)
        #expect(measured.warnings.contains { $0.kind == .advisory && $0.resourceGroup == .runtime && XcodeText.containsIgnoringCase($0.message, "controlli di sicurezza") })
        #expect(sizes.measuredPaths.values.isEmpty)
    }

    @Test func runtimeImagesWithoutAnAbsolutePathAreNotMeasured() async throws {
        let sizes = FakeSizeProbe()
        let original = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "runtime:11111111-1111-4111-8111-111111111111", kind: .runtime, name: "senza percorso", path: nil),
            XcodeCandidate(key: "runtime:22222222-2222-4222-8222-222222222222", kind: .runtime, name: "vuoto", path: ""),
            XcodeCandidate(key: "runtime:33333333-3333-4333-8333-333333333333", kind: .runtime, name: "spazi", path: "   "),
            XcodeCandidate(key: "runtime:44444444-4444-4444-8444-444444444444", kind: .runtime, name: "relativo", path: "relative/shared.dmg"),
        ], warnings: [])

        let measured = try await makeScanner(InMemoryFileSystem(), sizes).measureRuntimeBackingImages(original)

        #expect(measured.candidates.allSatisfy { $0.sizeBytes == nil })
        #expect(measured.warnings.filter { $0.kind == .advisory && XcodeText.containsIgnoringCase($0.message, "non disponibile") }.count == 4)
        #expect(sizes.measuredPaths.values.isEmpty)
    }
}
