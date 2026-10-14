/// Applica le classificazioni di sicurezza correnti senza introdurre alcuno stato di selezione.
public enum XcodeClassifier {
    private static let runtimePrefix = "runtime:"

    public static func classify(_ snapshot: XcodeSnapshot, xcodeRunning: Bool) throws -> XcodeSnapshot {
        var keys = Set<[UInt8]>()
        for candidate in snapshot.candidates {
            guard !XcodeText.isNullOrWhiteSpace(candidate.key),
                  keys.insert(XcodeText.ordinalKey(normalizeSelectionKey(candidate.key))).inserted else {
                throw XcodeArgumentError(String(localized: "Xcode inventory contains a missing or duplicate candidate key.", bundle: .module))
            }
        }

        var byKey: [[UInt8]: XcodeCandidate] = [:]
        for candidate in snapshot.candidates {
            byKey[XcodeText.ordinalKey(normalizeSelectionKey(candidate.key))] = candidate
        }

        let classified = snapshot.candidates.map { classifyCandidate($0, byKey, xcodeRunning) }
        return XcodeSnapshot(candidates: classified, warnings: snapshot.warnings, fileInventory: snapshot.fileInventory)
    }

    private static func classifyCandidate(
        _ candidate: XcodeCandidate,
        _ byKey: [[UInt8]: XcodeCandidate],
        _ xcodeRunning: Bool
    ) -> XcodeCandidate {
        var block = candidate.blockReason
        switch candidate.kind {
        case .derivedData, .deviceSupport:
            if xcodeRunning {
                block = block ?? String(localized: "Chiudi Xcode e ripeti l'analisi prima di rimuovere file.", bundle: .module)
            }
        case .device:
            let identityVerified = isMatchingUuid(candidate.key, candidate.cliId)
            if !identityVerified {
                block = block ?? String(localized: "Identità UUID del dispositivo non verificata.", bundle: .module)
            } else if isRunning(candidate.state) {
                block = String(localized: "Arresta il dispositivo in Xcode prima di rimuoverlo.", bundle: .module)
            } else if let state = candidate.state, isUnavailable(state) {
                // Si allenta solo l'avviso che il parser ricava dallo stato "Unavailable": ogni
                // altro avviso d'inventario o d'identità resta un blocco.
                let unavailableStateWarning = String(localized: "Stato del dispositivo non verificato: \(state); ripeti l'analisi.", bundle: .module)
                if let current = block, PathText.equalsIgnoringCase(current, unavailableStateWarning) {
                    block = nil
                }
            } else if !isShutdown(candidate.state) {
                block = block ?? String(localized: "Stato del dispositivo non verificato; ripeti l'analisi.", bundle: .module)
            }
        case .runtime:
            if !isRuntimeIdentityVerified(candidate) {
                block = block ?? String(localized: "Identità del runtime non verificata.", bundle: .module)
            }

            for dependencyKey in candidate.dependentDeviceKeys {
                guard let dependency = byKey[XcodeText.ordinalKey(normalizeSelectionKey(dependencyKey))],
                      dependency.kind == .device else {
                    block = block ?? String(localized: "Dipendenze del runtime non verificate; ripeti l'analisi.", bundle: .module)
                    continue
                }

                if isRunning(dependency.state) {
                    block = String(localized: "Un dispositivo che usa questo runtime è avviato; arrestalo in Xcode prima di rimuoverlo.", bundle: .module)
                    break
                }

                if !isShutdown(dependency.state) && !isUnavailable(dependency.state) {
                    block = block ?? String(localized: "Lo stato di un dispositivo che usa questo runtime non è verificato.", bundle: .module)
                }
            }
        }

        var classified = candidate
        classified.blockReason = block
        classified.dependencies = candidate.dependentDeviceKeys
        return classified
    }

    /// Un UUID, anche con prefisso "runtime:", nella forma canonica minuscola: due grafie dello
    /// stesso UUID selezionano la stessa riga. Ogni altra chiave resta com'è.
    static func normalizeSelectionKey(_ key: String) -> String {
        if let uuid = XcodeUuid.canonical(key) { return uuid }

        if PathText.hasPrefixIgnoringCase(key, runtimePrefix) {
            // Il prefisso riconosciuto occupa in `key` lo stesso numero di scalari di "runtime:".
            let rest = String(String.UnicodeScalarView(key.unicodeScalars.dropFirst(runtimePrefix.unicodeScalars.count)))
            if let uuid = XcodeUuid.canonical(rest) { return runtimePrefix + uuid }
        }

        return key
    }

    static func isRunning(_ state: String?) -> Bool {
        guard let state else { return false }
        return PathText.equalsIgnoringCase(state, "Booted")
            || PathText.equalsIgnoringCase(state, "Booting")
            || PathText.equalsIgnoringCase(state, "Starting")
    }

    static func isShutdown(_ state: String?) -> Bool {
        state.map { PathText.equalsIgnoringCase($0, "Shutdown") } ?? false
    }

    static func isUnavailable(_ state: String?) -> Bool {
        state.map { PathText.equalsIgnoringCase($0, "Unavailable") } ?? false
    }

    private static func isMatchingUuid(_ key: String, _ cliId: String?) -> Bool {
        guard let keyUuid = XcodeUuid.canonical(key), let cliId, let cliUuid = XcodeUuid.canonical(cliId) else { return false }
        return keyUuid == cliUuid
    }

    private static func isRuntimeIdentityVerified(_ candidate: XcodeCandidate) -> Bool {
        guard let cliId = candidate.cliId, let cliUuid = XcodeUuid.canonical(cliId),
              XcodeText.hasOrdinalPrefix(candidate.key, runtimePrefix) else { return false }
        let rest = String(decoding: candidate.key.utf8.dropFirst(runtimePrefix.utf8.count), as: UTF8.self)
        guard let keyUuid = XcodeUuid.canonical(rest) else { return false }
        return keyUuid == cliUuid
    }
}
