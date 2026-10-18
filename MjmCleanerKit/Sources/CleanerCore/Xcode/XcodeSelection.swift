/// L'anteprima di una selezione: cosa verrà rimosso, cosa resta e quanto spazio si stima.
public struct XcodeConfirmation: Sendable, Equatable {
    public let selectedCandidates: [XcodeCandidate]
    public let retainedDependentDevices: [XcodeCandidate]
    public let estimatedBytes: Int64
    public let unknownSizeCount: Int
    let sourceSnapshot: XcodeSnapshot

    /// Interno come il costruttore C#: solo `XcodeSelection` produce un'anteprima.
    init(
        sourceSnapshot: XcodeSnapshot,
        selectedCandidates: [XcodeCandidate],
        retainedDependentDevices: [XcodeCandidate],
        estimatedBytes: Int64,
        unknownSizeCount: Int
    ) {
        self.sourceSnapshot = sourceSnapshot
        self.selectedCandidates = selectedCandidates
        self.retainedDependentDevices = retainedDependentDevices
        self.estimatedBytes = estimatedBytes
        self.unknownSizeCount = unknownSizeCount
    }
}

/// Il piano confermato dall'utente: le sole risorse approvate e le identità delle cartelle da
/// riverificare prima di eliminarle.
public struct XcodeConfirmedPlan: Sendable, Equatable {
    public let candidates: [XcodeCandidate]
    public let fileInventory: XcodeFileInventory
    public let sourceSnapshot: XcodeSnapshot

    init(sourceSnapshot: XcodeSnapshot, candidates: [XcodeCandidate], fileInventory: XcodeFileInventory) {
        self.sourceSnapshot = sourceSnapshot
        self.candidates = candidates
        self.fileInventory = fileInventory
    }
}

public enum XcodeSelection {
    /// Le chiavi si esaminano in ordine ordinale: con più chiavi non valide l'errore riportato è
    /// sempre lo stesso (un `Set` Swift non ha l'ordine di inserimento dell'`HashSet` C#).
    public static func preview(_ snapshot: XcodeSnapshot, selectedKeys: Set<String>) throws -> XcodeConfirmation {
        let classified = try XcodeClassifier.classify(snapshot, xcodeRunning: false)

        var ordered: [(key: [UInt8], candidate: XcodeCandidate)] = []
        var candidatesByKey: [[UInt8]: XcodeCandidate] = [:]
        for candidate in classified.candidates {
            let normalized = XcodeText.ordinalKey(XcodeClassifier.normalizeSelectionKey(candidate.key))
            guard candidatesByKey[normalized] == nil else {
                throw XcodeArgumentError(String(localized: "Xcode inventory contains duplicate candidate keys.", bundle: .module))
            }
            candidatesByKey[normalized] = candidate
            ordered.append((normalized, candidate))
        }

        var selected = Set<[UInt8]>()
        for rawKey in selectedKeys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            let key = XcodeText.ordinalKey(XcodeClassifier.normalizeSelectionKey(rawKey))
            guard selected.insert(key).inserted else { continue }

            guard let candidate = candidatesByKey[key] else {
                throw XcodeArgumentError(String(localized: "Unknown Xcode candidate key: \(rawKey)", bundle: .module))
            }

            if let reason = candidate.blockReason {
                throw XcodeArgumentError(String(localized: "Xcode candidate is blocked: \(candidate.name): \(reason)", bundle: .module))
            }

            if isFileCandidate(candidate) && completeFileGuard(classified.fileInventory, candidate) == nil {
                throw XcodeArgumentError(String(localized: "Selected file candidate has no complete guarded inventory entry: \(candidate.name)", bundle: .module))
            }
        }

        let chosen = ordered.filter { selected.contains($0.key) }.map { copyCandidate($0.candidate) }
        let chosenKeys = Set(chosen.map { XcodeText.ordinalKey(XcodeClassifier.normalizeSelectionKey($0.key)) })

        var retained: [XcodeCandidate] = []
        var retainedKeys = Set<[UInt8]>()
        for runtime in chosen where runtime.kind == .runtime {
            for dependencyKey in runtime.dependentDeviceKeys {
                let key = XcodeText.ordinalKey(XcodeClassifier.normalizeSelectionKey(dependencyKey))
                guard !chosenKeys.contains(key),
                      let device = candidatesByKey[key], device.kind == .device,
                      retainedKeys.insert(key).inserted else { continue }
                retained.append(copyCandidate(device))
            }
        }

        let unknownCount = chosen.filter { $0.sizeBytes == nil }.count
        let knownBytes = chosen.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        return XcodeConfirmation(
            sourceSnapshot: copySnapshot(classified),
            selectedCandidates: chosen,
            retainedDependentDevices: retained,
            estimatedBytes: knownBytes,
            unknownSizeCount: unknownCount)
    }

    public static func confirm(_ preview: XcodeConfirmation, acknowledgeDependencies: Bool) throws -> XcodeConfirmedPlan {
        guard !preview.selectedCandidates.isEmpty else {
            throw XcodeOperationError(String(localized: "No Xcode resources were selected.", bundle: .module))
        }

        if !preview.retainedDependentDevices.isEmpty && !acknowledgeDependencies {
            throw XcodeOperationError(String(localized: "Acknowledge the retained devices that depend on the selected runtime.", bundle: .module))
        }

        let copied = preview.selectedCandidates.map(copyCandidate)
        var inventory: [(key: String, entry: XcodeFileEntry)] = []
        for candidate in copied where isFileCandidate(candidate) {
            guard let entry = completeFileGuard(preview.sourceSnapshot.fileInventory, candidate) else {
                throw XcodeOperationError(String(localized: "Selected file candidate lost its guarded inventory entry: \(candidate.name)", bundle: .module))
            }
            inventory.append((candidate.key, entry))
        }

        return XcodeConfirmedPlan(sourceSnapshot: preview.sourceSnapshot, candidates: copied, fileInventory: XcodeFileInventory(inventory))
    }

    private static func isFileCandidate(_ candidate: XcodeCandidate) -> Bool {
        candidate.kind == .derivedData || candidate.kind == .deviceSupport
    }

    /// La voce dell'inventario se è completa e coerente con la riga, altrimenti `nil`.
    private static func completeFileGuard(_ inventory: XcodeFileInventory, _ candidate: XcodeCandidate) -> XcodeFileEntry? {
        guard let path = candidate.path, let found = inventory[candidate.key] else { return nil }

        let identity = found.identity
        let complete = !XcodeText.isNullOrWhiteSpace(identity.canonicalPath)
            && XcodeText.same(path, identity.canonicalPath)
            && XcodeText.same(found.item.path, identity.canonicalPath)
            && found.item.isDirectory
            && identity.isDirectory
            && !XcodeText.isNullOrWhiteSpace(found.item.declaredRoot)
            && identity.creationTime != nil
            && identity.lastWriteTime != nil
        return complete ? found : nil
    }

    private static func copySnapshot(_ source: XcodeSnapshot) -> XcodeSnapshot {
        XcodeSnapshot(candidates: source.candidates.map(copyCandidate), warnings: source.warnings, fileInventory: source.fileInventory)
    }

    private static func copyCandidate(_ candidate: XcodeCandidate) -> XcodeCandidate {
        var copy = candidate
        copy.dependencies = candidate.dependentDeviceKeys
        return copy
    }
}
