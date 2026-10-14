import Darwin

/// `IXcodeFileScanner`.
public protocol XcodeFileScanning: Sendable {
    func scan() async throws -> XcodeSnapshot
    func measureRuntimeBackingImages(_ snapshot: XcodeSnapshot) async throws -> XcodeSnapshot
}

/// Scansiona solo le cartelle approvate della cache utente di Xcode: DerivedData e i Device
/// Support delle quattro piattaforme. Archives e UserData non sono mai candidati.
public struct XcodeFileScanner: XcodeFileScanning {
    private static let platforms = ["iOS", "watchOS", "tvOS", "visionOS"]

    private let fileSystem: any FileSystem
    private let ruleScanner: RuleScanner
    private let pathGuard: any PathGuarding
    private let links: any LinkInspecting
    private let sizeProbe: any XcodeSizeProbing
    private let homeDirectory: String

    public init(
        fileSystem: any FileSystem,
        ruleScanner: RuleScanner,
        pathGuard: any PathGuarding,
        links: any LinkInspecting,
        sizeProbe: any XcodeSizeProbing,
        homeDirectory: String
    ) {
        self.fileSystem = fileSystem
        self.ruleScanner = ruleScanner
        self.pathGuard = pathGuard
        self.links = links
        self.sizeProbe = sizeProbe
        self.homeDirectory = homeDirectory
    }

    private struct ScanState {
        var candidates: [XcodeCandidate] = []
        var warnings: [XcodeInventoryWarning] = []
        var inventory: [(key: String, entry: XcodeFileEntry)] = []
        var inventoryKeys = Set<[UInt8]>()
    }

    @concurrent
    public func scan() async throws -> XcodeSnapshot {
        var state = ScanState()
        let xcodeRoot = PathText.join(PathText.join(PathText.join(homeDirectory, "Library"), "Developer"), "Xcode")

        try await scanRoot(PathText.join(xcodeRoot, "DerivedData"), .derivedData, platform: nil, &state)
        for platform in Self.platforms {
            try await scanRoot(PathText.join(xcodeRoot, "\(platform) DeviceSupport"), .deviceSupport, platform: platform, &state)
        }

        return XcodeSnapshot(candidates: state.candidates, warnings: state.warnings, fileInventory: XcodeFileInventory(state.inventory))
    }

    private func scanRoot(_ root: String, _ kind: XcodeResourceKind, platform: String?, _ state: inout ScanState) async throws {
        try Task.checkCancellation()

        if !fileSystem.directoryExists(root) {
            // Directory.Exists è falso anche per una cartella che non si può leggere: elencarla
            // distingue l'assenza vera (nessun avviso) dall'accesso negato (inventario incompleto).
            do {
                _ = try fileSystem.contentsOfDirectory(root)
            } catch let error as FileSystemError {
                switch error.code {
                case ENOENT, ENOTDIR:
                    // La root nota è davvero assente.
                    break
                case EACCES, EPERM, EBADF:
                    state.warnings.append(.completenessFailure(kind, String(localized: "Root Xcode non accessibile: \(root)", bundle: .module)))
                default:
                    state.warnings.append(.completenessFailure(kind, String(localized: "Impossibile verificare la root Xcode: \(root)", bundle: .module)))
                }
            }
            return
        }

        if links.isSymbolicLink(root) {
            state.warnings.append(.completenessFailure(kind, String(localized: "La root Xcode è un collegamento simbolico e non viene scansionata: \(root)", bundle: .module)))
            return
        }

        let outcome = try ruleScanner.scan(CleanupRule(root, .matchingDirs, include: ["*"], exclude: [], maxDepth: 1))
        if !outcome.errors.isEmpty || !outcome.exclusions.isEmpty {
            state.warnings.append(.completenessFailure(kind, String(localized: "Inventario incompleto: alcune cartelle non sono leggibili o non superano i controlli di percorso.", bundle: .module)))
        }

        for item in outcome.items {
            try Task.checkCancellation()
            // La regola dei figli diretti produce solo cartelle, ma il confine dei collegamenti si
            // ricontrolla subito prima di leggere metadati e dimensione.
            let verdict = pathGuard.validate(item.path, declaredRoot: root)
            guard verdict.isAllowed, !links.isSymbolicLink(item.path), fileSystem.directoryExists(item.path) else {
                state.warnings.append(.completenessFailure(kind, String(localized: "Una cartella Xcode è stata saltata perché è cambiata o non è sicura: \(PathText.fileName(item.path))", bundle: .module)))
                continue
            }

            let canonical = verdict.canonicalPathValidated
            let key = kind == .derivedData ? "derived-data:\(canonical)" : "device-support:\(platform ?? ""):\(canonical)"
            guard !state.inventoryKeys.contains(XcodeText.ordinalKey(key)) else { continue }

            let info: FileItemInfo
            do {
                info = try fileSystem.itemInfo(canonical)
            } catch is FileSystemError {
                state.warnings.append(.completenessFailure(kind, String(localized: "Una cartella Xcode è stata saltata perché i metadati non sono leggibili: \(PathText.fileName(item.path))", bundle: .module)))
                continue
            }

            let allocated = try await sizeProbe.measure(canonical)
            let partial = outcome.errors.contains { Self.isAtOrBelow($0.path, canonical) }
            let identity = XcodeFileIdentity(
                canonicalPath: canonical,
                isDirectory: true,
                creationTime: info.creation,
                lastWriteTime: info.lastWrite,
                logicalSizeBytes: partial ? nil : item.sizeBytes)
            let guardedItem = ScanItem(path: canonical, sizeBytes: item.sizeBytes, isDirectory: item.isDirectory, declaredRoot: root)
            state.inventory.append((key, XcodeFileEntry(item: guardedItem, identity: identity)))
            state.inventoryKeys.insert(XcodeText.ordinalKey(key))

            let name = PathText.fileName(canonical)
            state.candidates.append(XcodeCandidate(
                key: key,
                kind: kind,
                name: platform.map { "\($0): \(name)" } ?? name,
                path: canonical,
                sizeBytes: allocated,
                blockReason: partial
                    ? String(localized: "Scansione parziale: impossibile verificare l'identità completa della cartella.", bundle: .module)
                    : nil))
        }
    }

    private static func isAtOrBelow(_ candidatePath: String, _ rootPath: String) -> Bool {
        PathText.equalsIgnoringCase(candidatePath, rootPath)
            || PathText.hasPrefixIgnoringCase(candidatePath, PathText.trimmingTrailingSlashes(rootPath) + "/")
    }

    /// Misura le immagini runtime dichiarate dalla CLI, mai i percorsi dei volumi montati.
    @concurrent
    public func measureRuntimeBackingImages(_ snapshot: XcodeSnapshot) async throws -> XcodeSnapshot {
        var warnings = snapshot.warnings
        var candidates = snapshot.candidates
        var seenPaths = Set<[UInt8]>()
        var firstPath: String?

        for (index, candidate) in snapshot.candidates.enumerated() where candidate.kind == .runtime {
            try Task.checkCancellation()
            var measured = candidate
            measured.sizeBytes = nil

            guard let path = candidate.path, !XcodeText.isNullOrWhiteSpace(path), path.utf8.first == UInt8(ascii: "/") else {
                candidates[index] = measured
                warnings.append(.advisory(.runtime, String(localized: "Dimensione sconosciuta per \(candidate.name): percorso dell'immagine runtime non disponibile.", bundle: .module)))
                continue
            }

            guard let root = PathText.parent(path) else {
                candidates[index] = measured
                warnings.append(.advisory(.runtime, String(localized: "Dimensione sconosciuta per \(candidate.name): percorso dell'immagine runtime non valido.", bundle: .module)))
                continue
            }

            let rootVerdict = pathGuard.validateRoot(root)
            let verdict = rootVerdict.isAllowed ? pathGuard.validate(path, declaredRoot: root) : rootVerdict
            guard verdict.isAllowed, !links.isSymbolicLink(path) else {
                candidates[index] = measured
                warnings.append(.advisory(.runtime, String(localized: "Dimensione sconosciuta per \(candidate.name): il percorso dell'immagine non supera i controlli di sicurezza.", bundle: .module)))
                continue
            }

            let canonical = verdict.canonicalPathValidated
            measured.path = canonical
            guard seenPaths.insert(XcodeText.ordinalKey(canonical)).inserted else {
                candidates[index] = measured
                warnings.append(.advisory(.runtime, String(localized: "Immagine runtime condivisa con \(firstPath ?? ""): la dimensione viene conteggiata una sola volta.", bundle: .module)))
                continue
            }

            firstPath = canonical
            measured.sizeBytes = try await sizeProbe.measure(canonical)
            candidates[index] = measured
        }

        return XcodeSnapshot(candidates: candidates, warnings: warnings, fileInventory: snapshot.fileInventory)
    }
}
