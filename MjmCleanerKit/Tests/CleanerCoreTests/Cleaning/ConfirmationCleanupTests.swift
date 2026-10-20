import Testing
@testable import CleanerCore

/// La garanzia del passo 3 dalle righe al disco (spec `2026-10-20-confirmation-containment-design.md`):
/// le righe si costruiscono con le root risolte da un vero `PathGuard`, la selezione passa da
/// `ConfirmationRows.selections` e la cancella un vero `CleanEngine`, su `InMemoryFileSystem`.
/// `~/.cache` è un collegamento a `~/Dati/cache`, e «File grandi» guarda `~/Dati`.
struct ConfirmationCleanupTests {
    private static let home = "/Users/tester"
    private static let cacheRoot = "/Users/tester/.cache"
    private static let dataRoot = "/Users/tester/Dati"
    private static let folder = "/Users/tester/Dati/cache/huggingface"
    private static let model = "/Users/tester/Dati/cache/huggingface/hub/model.bin"
    private static let config = "/Users/tester/Dati/cache/huggingface/hub/config.json"

    private let fileSystem = InMemoryFileSystem()
    private let pathGuard: PathGuard

    init() throws {
        fileSystem.addFile(Self.model, size: 4_800)
        fileSystem.addFile(Self.config, size: 10)
        pathGuard = try PathGuard(
            denyList: DenyList(homeDirectory: Self.home), fileSystem: fileSystem,
            links: FakeLinkInspector(targets: [Self.cacheRoot: "\(Self.dataRoot)/cache"]), homeDirectory: Self.home)
    }

    private var rows: [ConfirmationCategory] {
        ConfirmationRows.build(
            [
                CategoryScanResult(
                    categoryId: "dev-caches",
                    items: [ScanItem(path: "\(Self.cacheRoot)/huggingface", sizeBytes: 4_810, isDirectory: true, declaredRoot: Self.cacheRoot)],
                    totalBytes: 4_810, errors: [], exclusions: []),
                CategoryScanResult(
                    categoryId: "large-files",
                    items: [ScanItem(path: Self.model, sizeBytes: 4_800, isDirectory: false, declaredRoot: Self.dataRoot)],
                    totalBytes: 4_800, errors: [], exclusions: []),
            ],
            resolveRoot: pathGuard.resolvedRoot)
    }

    private func clean(selected: Set<ConfirmationPosition>) async -> CleanReport {
        let engine = CleanEngine(fileSystem: fileSystem, pathGuard: pathGuard, clock: FixedWallClock(now: utc(2026, 10, 20, 12)))
        return await engine.clean(ConfirmationRows.selections(rows) { selected.contains($0) }, progress: nil, journal: nil)
    }

    @Test func theModelIsBoundToTheFolderItLivesIn() {
        #expect(rows.map { $0.rows.map(\.container) } == [[nil], [ConfirmationPosition(category: 0, row: 0)]])
    }

    /// Cartella spuntata, modello deselezionato: il modello sparisce con la cartella (per questo il
    /// passo 3 lo mostra spuntato), una sola voce cancellata e byte contati una volta.
    @Test func aTickedFolderTakesTheModelWithItAndCountsItOnce() async {
        let report = await clean(selected: [ConfirmationPosition(category: 0, row: 0)])

        #expect(!fileSystem.fileExists(Self.model))
        #expect(!fileSystem.directoryExists(Self.folder))
        #expect(report.itemsDeleted == 1)
        #expect(report.bytesFreed == 4_810)
        #expect(report.errors.isEmpty)
    }

    /// Cartella e modello entrambi spuntati: prima del contenimento il modello partiva da solo dopo la
    /// cartella e finiva fra gli errori con ENOENT, e il totale contava due volte i suoi byte.
    @Test func aTickedFolderAndATickedModelInsideItAreDeletedOnce() async {
        let report = await clean(selected: [ConfirmationPosition(category: 0, row: 0), ConfirmationPosition(category: 1, row: 0)])

        #expect(!fileSystem.directoryExists(Self.folder))
        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 0)
        #expect(report.errors.isEmpty)
        #expect(report.bytesFreed == 4_810)
    }

    /// Cartella deselezionata: si cancella solo ciò che è spuntato, e il resto della cartella resta.
    @Test func anUntickedFolderKeepsEverythingButTheTickedModel() async {
        let report = await clean(selected: [ConfirmationPosition(category: 1, row: 0)])

        #expect(!fileSystem.fileExists(Self.model))
        #expect(fileSystem.fileExists(Self.config))
        #expect(report.itemsDeleted == 1)
        #expect(report.bytesFreed == 4_800)
    }

    @Test func nothingTickedDeletesNothing() async {
        let report = await clean(selected: [])

        #expect(fileSystem.fileExists(Self.model))
        #expect(fileSystem.fileExists(Self.config))
        #expect(report.itemsDeleted == 0)
    }
}
