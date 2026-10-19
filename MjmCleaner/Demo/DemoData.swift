#if DEBUG
import CleanerCore
import Foundation

/// I dati fissi dell'avvio dimostrativo: plausibili, mai letti dal disco.
enum DemoData {
    private static let gigabyte: Int64 = 1_073_741_824
    private static let megabyte: Int64 = 1_048_576
    private static let startedAt = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Pulizia

    static let analyzedCategoryIds = ["system-caches", "dev-caches", "nuget-packages", "logs"]

    static let scanProgress = [
        ScanProgress(categoryId: "system-caches", currentPath: "/Users/demo/Library/Caches/com.apple.Safari", itemsFound: 214, bytesFound: 3 * gigabyte),
        ScanProgress(categoryId: "dev-caches", currentPath: "/Users/demo/Library/Caches/org.swift.swiftpm", itemsFound: 38, bytesFound: 2 * gigabyte),
    ]

    static let scanResults = [
        result("system-caches", [
            item("/Users/demo/Library/Caches/com.apple.Safari", 1_350 * megabyte),
            item("/Users/demo/Library/Caches/com.spotify.client", 820 * megabyte),
            item("/Users/demo/Library/Caches/Google/Chrome", 640 * megabyte),
        ]),
        result("dev-caches", [
            item("/Users/demo/Library/Caches/org.swift.swiftpm", 1_100 * megabyte),
            item("/Users/demo/.npm/_cacache", 730 * megabyte),
        ]),
        result("nuget-packages", [
            item("/Users/demo/.nuget/packages/newtonsoft.json/12.0.3", 18 * megabyte),
        ]),
        result("logs", [
            item("/Users/demo/Library/Logs/DiagnosticReports", 96 * megabyte),
        ]),
    ]

    static let cleanReport = CleanReport(
        startedAt: startedAt,
        duration: .seconds(12),
        bytesFreed: 4_754 * megabyte,
        itemsDeleted: 7,
        itemsFailed: 1,
        categories: [
            CategoryCleanResult(categoryId: "system-caches", bytesFreed: 2_810 * megabyte, itemsDeleted: 3),
            CategoryCleanResult(categoryId: "dev-caches", bytesFreed: 1_830 * megabyte, itemsDeleted: 2),
            CategoryCleanResult(categoryId: "logs", bytesFreed: 96 * megabyte, itemsDeleted: 1),
            CategoryCleanResult(categoryId: "nuget-packages", bytesFreed: 18 * megabyte, itemsDeleted: 1),
        ],
        errors: [ScanError(path: "/Users/demo/Library/Caches/com.apple.Safari/WebKit", kind: .inUse, message: "risorsa occupata")],
        deletedPaths: [])

    static let sessions = [
        CleanSessionSummary(
            id: 3, startedAt: startedAt, duration: .seconds(12), bytesFreed: 4_754 * megabyte, itemsDeleted: 7, itemsFailed: 1,
            categories: cleanReport.categories),
        CleanSessionSummary(
            id: 2, startedAt: startedAt.addingTimeInterval(-6 * 86_400), duration: .seconds(40), bytesFreed: 3 * gigabyte, itemsDeleted: 2_117, itemsFailed: 0,
            categories: [
                CategoryCleanResult(categoryId: "project-build-output", bytesFreed: 2 * gigabyte, itemsDeleted: 2_100),
                CategoryCleanResult(categoryId: "trash", bytesFreed: gigabyte, itemsDeleted: 17),
            ]),
        CleanSessionSummary(
            id: 1, startedAt: startedAt.addingTimeInterval(-20 * 86_400), duration: .seconds(5), bytesFreed: 1_843 * megabyte, itemsDeleted: 3, itemsFailed: 0,
            categories: [
                CategoryCleanResult(categoryId: DockerCategories.images, bytesFreed: 1_200 * megabyte, itemsDeleted: 2),
                CategoryCleanResult(categoryId: DockerCategories.buildCache, bytesFreed: 643 * megabyte, itemsDeleted: 1),
            ]),
    ]

    // MARK: Docker

    static let diskBefore = DockerDiskUsage(path: "/Users/demo/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", allocatedBytes: 24 * gigabyte, apparentBytes: 64 * gigabyte)
    static let diskAfter = DockerDiskUsage(path: diskBefore.path, allocatedBytes: 24 * gigabyte, apparentBytes: 64 * gigabyte)

    static let dockerAnalysis = DockerAnalysis(
        engine: DockerEngine(serverVersion: "27.3.1", operatingSystem: "Docker Desktop"),
        snapshot: DockerSnapshot(
            containers: [], images: [], volumes: [],
            df: DockerDfSummary(entries: [
                DockerDfEntry(type: DockerDfSummary.imagesType, sizeBytes: 14 * gigabyte, reclaimableBytes: 9 * gigabyte),
                DockerDfEntry(type: DockerDfSummary.volumesType, sizeBytes: 3 * gigabyte, reclaimableBytes: 2 * gigabyte),
                DockerDfEntry(type: DockerDfSummary.buildCacheType, sizeBytes: 2 * gigabyte, reclaimableBytes: 2 * gigabyte),
            ]),
            existingComposeProjects: []),
        candidates: [
            docker(.image, "sha256:4f1c", "<none>:<none>", 1_200 * megabyte, .delete, "dangling", "Immagine dangling: nessun tag la nomina."),
            docker(.buildCache, "build-cache", "cache di build", 2 * gigabyte, .delete, "build-cache", "Cache di build: si rigenera alla prossima build."),
            docker(.image, "sha256:9a2b", "shop-api:dev", 850 * megabyte, .ask, "local-build", "Costruita in locale dal Dockerfile di ~/Progetti/shop."),
            docker(.image, "sha256:77c0", "postgres:15", 412 * megabyte, .propose, "unused-image", "Nessun container la usa.", cost: "riscaricarla"),
            docker(.volume, "a1b2c3d4", "a1b2c3d4", 300 * megabyte, .propose, "anonymous-unused", "Volume anonimo non montato."),
            docker(.volume, "shop_pgdata", "shop_pgdata", 1_100 * megabyte, .propose, "named-unused", "Nessuna regola lo riconduce a un progetto."),
            docker(.image, "sha256:c3d4", "redis:7", 140 * megabyte, .keep, "in-use", "In uso da un container."),
        ],
        disk: diskBefore)

    static let dockerResult = DockerCleanResult(
        report: CleanReport(
            startedAt: startedAt, duration: .seconds(9), bytesFreed: 3_200 * megabyte, itemsDeleted: 2, itemsFailed: 1,
            categories: [], errors: [ScanError(path: "docker:image:sha256:9a2b", kind: .inUse, message: "image is being used by a stopped container")],
            deletedPaths: ["docker:image:sha256:4f1c (<none>:<none>)", "docker:build-cache"]),
        before: dockerAnalysis.snapshot.df,
        after: DockerDfSummary(entries: [
            DockerDfEntry(type: DockerDfSummary.imagesType, sizeBytes: 12 * gigabyte, reclaimableBytes: 7 * gigabyte),
        ]),
        daemonLost: false)

    // MARK: Xcode

    /// La cartella DerivedData di ShopApp, con la sua voce nell'inventario dei file, e il runtime usato
    /// da un dispositivo che resta: l'anteprima mostra sia la cartella da eliminare sia la presa d'atto.
    static let previewedXcodeKeys = [shopDerivedData.key, runtime.key]

    private static let shopDerivedData = XcodeCandidate(
        key: "DerivedData/ShopApp", kind: .derivedData, name: "ShopApp-abcdefgh",
        path: "/Users/demo/Library/Developer/Xcode/DerivedData/ShopApp-abcdefgh", sizeBytes: 3 * gigabyte)
    private static let widgetsDerivedData = XcodeCandidate(
        key: "DerivedData/Widgets", kind: .derivedData, name: "Widgets-ijklmnop",
        path: "/Users/demo/Library/Developer/Xcode/DerivedData/Widgets-ijklmnop", sizeBytes: 900 * megabyte)
    private static let deviceSupport = XcodeCandidate(
        key: "DeviceSupport/17.4", kind: .deviceSupport, name: "iOS 17.4 (21E219)",
        path: "/Users/demo/Library/Developer/Xcode/iOS DeviceSupport/17.4 (21E219)", sizeBytes: 4 * gigabyte)
    private static let iPhone = XcodeCandidate(
        key: "8C1F0B6E-0000-4000-8000-000000000001", kind: .device, name: "iPhone 15",
        cliId: "8C1F0B6E-0000-4000-8000-000000000001", state: "Shutdown", sizeBytes: 2 * gigabyte)
    private static let iPad = XcodeCandidate(
        key: "2A7E0B6E-0000-4000-8000-000000000002", kind: .device, name: "iPad Air",
        cliId: "2A7E0B6E-0000-4000-8000-000000000002", state: "Booted", sizeBytes: 1_500 * megabyte,
        blockReason: "In esecuzione: chiudilo per eliminarlo.")
    private static let runtime = XcodeCandidate(
        key: "runtime:5D1E0B6E-0000-4000-8000-000000000003", kind: .runtime, name: "iOS 17.4",
        cliId: "5D1E0B6E-0000-4000-8000-000000000003", sizeBytes: 7 * gigabyte,
        dependencies: ["8C1F0B6E-0000-4000-8000-000000000001"])

    static let xcodeSnapshot = XcodeSnapshot(
        candidates: [shopDerivedData, widgetsDerivedData, deviceSupport, iPhone, iPad, runtime],
        warnings: [],
        fileInventory: XcodeFileInventory([
            xcodeFileEntry(shopDerivedData, declaredRoot: "/Users/demo/Library/Developer/Xcode/DerivedData"),
            xcodeFileEntry(widgetsDerivedData, declaredRoot: "/Users/demo/Library/Developer/Xcode/DerivedData"),
            xcodeFileEntry(deviceSupport, declaredRoot: "/Users/demo/Library/Developer/Xcode/iOS DeviceSupport"),
        ]))

    static let xcodeResult = XcodeCleanResult(
        historyReport: CleanReport(
            startedAt: startedAt, duration: .seconds(31), bytesFreed: 10 * gigabyte, itemsDeleted: 2, itemsFailed: 0,
            categories: [], errors: [], deletedPaths: []),
        items: [
            XcodeItemResult(candidate: shopDerivedData, outcome: .deleted, reason: "Cartella eliminata.", verifiedEstimatedBytes: 3 * gigabyte),
            XcodeItemResult(candidate: runtime, outcome: .deleted, reason: "Runtime rimosso da simctl.", verifiedEstimatedBytes: 7 * gigabyte),
            XcodeItemResult(candidate: iPad, outcome: .skipped, reason: "In esecuzione: chiudilo per eliminarlo.", verifiedEstimatedBytes: nil),
        ],
        freeBytesBefore: 120 * gigabyte,
        freeBytesAfter: 131 * gigabyte,
        warnings: [])

    // MARK: Costruttori

    private static func item(_ path: String, _ size: Int64) -> ScanItem {
        ScanItem(path: path, sizeBytes: size, isDirectory: true, declaredRoot: path)
    }

    private static func result(_ categoryId: String, _ items: [ScanItem]) -> CategoryScanResult {
        CategoryScanResult(
            categoryId: categoryId, items: items, totalBytes: items.reduce(0) { $0 + $1.sizeBytes },
            errors: [], exclusions: [])
    }

    private static func xcodeFileEntry(_ candidate: XcodeCandidate, declaredRoot: String) -> (key: String, entry: XcodeFileEntry) {
        guard let path = candidate.path, let sizeBytes = candidate.sizeBytes else {
            preconditionFailure("La fixture Xcode deve avere percorso e dimensione per ogni cartella selezionabile.")
        }
        let item = ScanItem(path: path, sizeBytes: sizeBytes, isDirectory: true, declaredRoot: declaredRoot)
        let identity = XcodeFileIdentity(
            canonicalPath: path,
            isDirectory: true,
            creationTime: startedAt,
            lastWriteTime: startedAt,
            logicalSizeBytes: sizeBytes)
        return (candidate.key, XcodeFileEntry(item: item, identity: identity))
    }

    private static func docker(
        _ kind: DockerResourceKind, _ id: String, _ name: String, _ size: Int64, _ verdict: DockerVerdict,
        _ rule: String, _ reason: String, cost: String = ""
    ) -> DockerCandidate {
        DockerCandidate(kind: kind, id: id, displayName: name, sizeBytes: size, verdict: verdict, ruleId: rule, reason: reason, cost: cost)
    }
}
#endif
