import Foundation
import Testing
@testable import CleanerCore

/// Catena Xcode reale su una cartella temporanea: scansione con `du` vero, identità letta da
/// APFS (data di nascita e di modifica), riverifica, cancellazione tramite `CleanEngine` e diario.
/// La home di prova vive sotto $TMPDIR, quindi la root passa per la risoluzione /var → /private/var.
struct XcodeRealFileSystemTests {
    private struct EmptyCli: XcodeCliInvoking {
        func readInventory() async throws -> XcodeSnapshot { .empty }
        func deleteDevice(_ uuid: String) async throws -> ProcessResult { throw XcodeOperationError("non usato") }
        func deleteRuntime(_ uuid: String) async throws -> ProcessResult { throw XcodeOperationError("non usato") }
    }

    /// Xcode può essere aperto sulla macchina che esegue i test: lo stato è fissato.
    private struct ClosedXcode: XcodeRunningProbing {
        func state() async throws -> XcodeRunningState { .notRunning }
    }

    private struct JournalRecorder: DeletionRecording {
        let paths = Recorder<String>()

        func recordDeleted(_ path: String) {
            paths.append(path)
        }
    }

    private struct Fixture {
        let tmp: TemporaryDirectory
        let derivedData: String
        let collector: XcodeInventoryCollector
        let executor: XcodeCleanExecutor

        init() throws {
            tmp = try TemporaryDirectory()
            let home = try tmp.directory("home")
            derivedData = try tmp.directory("home/Library/Developer/Xcode/DerivedData")
            let fs = LocalFileSystem()
            let links = FileSystemLinkInspector()
            let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), fileSystem: fs, links: links, homeDirectory: home)
            let sizes = XcodeSizeProbe(fileSystem: fs, runner: ProcessRunner(), links: links, homeDirectory: home)
            let scanner = XcodeFileScanner(
                fileSystem: fs, ruleScanner: RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: SystemWallClock()),
                pathGuard: pathGuard, links: links, sizeProbe: sizes, homeDirectory: home)
            collector = XcodeInventoryCollector(cli: EmptyCli(), fileScanner: scanner)
            executor = XcodeCleanExecutor(
                cli: EmptyCli(), collector: collector, cleanEngine: CleanEngine(fileSystem: fs, pathGuard: pathGuard, clock: SystemWallClock()),
                measures: sizes, runningProbe: ClosedXcode(), clock: SystemWallClock())
        }

        func plan(for name: String) async throws -> XcodeConfirmedPlan {
            let snapshot = try await collector.collect()
            let key = try #require(snapshot.candidates.first { $0.name == name }?.key)
            return try XcodeSelection.confirm(XcodeSelection.preview(snapshot, selectedKeys: [key]), acknowledgeDependencies: true)
        }
    }

    @Test func derivedDataFolderIsScannedRevalidatedDeletedAndJournaled() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Library/Developer/Xcode/DerivedData/App-abc/Build/Products/app", contents: String(repeating: "x", count: 100))
        try fixture.tmp.file("home/Library/Developer/Xcode/DerivedData/Keep-xyz/Index/store", contents: "y")
        let journal = JournalRecorder()

        let plan = try await fixture.plan(for: "App-abc")
        let result = await fixture.executor.execute(plan, progress: nil, journal: journal)

        let item = try #require(result.items.first)
        #expect(result.items.count == 1)
        #expect(item.outcome == .deleted)
        #expect((item.verifiedEstimatedBytes ?? 0) > 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.derivedData + "/App-abc"))
        #expect(FileManager.default.fileExists(atPath: fixture.derivedData + "/Keep-xyz/Index/store"))
        // Il diario riceve il percorso che CleanEngine ha eliminato: quello risolto dal guard.
        let journaled = try #require(journal.paths.values.first)
        #expect(journal.paths.values.count == 1)
        #expect(XcodeText.hasOrdinalPrefix(journaled, "/private/var/"))
        #expect(PathText.fileName(journaled) == "App-abc")
        #expect(result.historyReport.itemsDeleted == 1)
    }

    @Test func folderChangedAfterAnalysisIsSkippedAndKept() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Library/Developer/Xcode/DerivedData/App-abc/Build/app", contents: "x")
        let journal = JournalRecorder()

        let plan = try await fixture.plan(for: "App-abc")
        try fixture.tmp.file("home/Library/Developer/Xcode/DerivedData/App-abc/nuovo.bin", contents: String(repeating: "z", count: 4096))
        let result = await fixture.executor.execute(plan, progress: nil, journal: journal)

        let item = try #require(result.items.first)
        #expect(item.outcome == .skipped)
        #expect(item.reason == "Il percorso o i metadati della cartella sono cambiati dall'analisi.")
        #expect(FileManager.default.fileExists(atPath: fixture.derivedData + "/App-abc/Build/app"))
        #expect(journal.paths.values.isEmpty)
    }
}
