/// Il confine dell'inventario verso l'applicazione: la gestione della CLI resta in
/// `XcodeCliInvoking`, le cartelle in `XcodeFileScanning`.
public struct XcodeInventoryCollector: XcodeInventoryCollecting {
    private let cli: any XcodeCliInvoking
    private let fileScanner: (any XcodeFileScanning)?

    public init(cli: any XcodeCliInvoking, fileScanner: (any XcodeFileScanning)? = nil) {
        self.cli = cli
        self.fileScanner = fileScanner
    }

    public func collect() async throws -> XcodeSnapshot {
        let cliSnapshot = try await cli.readInventory()
        guard let fileScanner else { return cliSnapshot }

        let fileSnapshot = try await fileScanner.scan()
        let combined = XcodeSnapshot(
            candidates: cliSnapshot.candidates + fileSnapshot.candidates,
            warnings: cliSnapshot.warnings + fileSnapshot.warnings,
            fileInventory: fileSnapshot.fileInventory)
        return try await fileScanner.measureRuntimeBackingImages(combined)
    }
}
