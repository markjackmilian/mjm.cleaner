/// Interpreta i due formati d'inventario di `simctl`, indipendenti e in sola lettura.
public enum XcodeJson {
    private struct LogicalRuntime {
        let identifier: String
        let build: String
        let name: String
        let version: String?
        let platform: String?
    }

    private struct RuntimeImage {
        let id: String
        let cliId: String?
        let runtimeIdentifier: String?
        let build: String?
        let version: String?
        let state: String?
        let backingPath: String?
        let deletable: Bool?
    }

    /// Errore di struttura con un testo proprio: l'equivalente dei `JsonException` lanciati dal C#.
    private struct StructureError: Error, CustomStringConvertible {
        let description: String
    }

    public static func parseInventory(_ simctlJson: String?, _ runtimeJson: String?, runtimeDeleteSupported: Bool) -> XcodeSnapshot {
        var candidates: [XcodeCandidate] = []
        var warnings: [XcodeInventoryWarning] = []
        var logicalRuntimes: [LogicalRuntime] = []
        var devices: [XcodeCandidate] = []
        var conflictingDeviceRuntimes = Set<[UInt8]>()
        var deviceInventorySafe = true
        var logicalRuntimeInventorySafe = true
        var runtimeInventorySafe = true

        func hasWarning(_ group: XcodeResourceKind, _ kind: XcodeInventoryWarningKind) -> Bool {
            warnings.contains { $0.resourceGroup == group && $0.kind == kind }
        }

        var simctlRoot: XcodeJsonValue?
        do {
            let document = try XcodeJsonReader.parse(simctlJson ?? "")
            guard case .object = document else {
                throw StructureError(description: String(localized: "L'inventario simulatori non è un oggetto JSON.", bundle: .module))
            }
            simctlRoot = document
        } catch {
            deviceInventorySafe = false
            logicalRuntimeInventorySafe = false
            warnings.append(.completenessFailure(.device, String(localized: "Inventario simulatori non leggibile: \(XcodeText.message(error))", bundle: .module)))
            warnings.append(.completenessFailure(.runtime, String(localized: "Inventario dei runtime logici non leggibile.", bundle: .module)))
        }

        if let root = simctlRoot {
            if case .array(let runtimeArray)? = root.property("runtimes") {
                for runtime in runtimeArray {
                    guard let identifier = runtime.string("identifier"),
                          let build = runtime.string("buildversion") ?? runtime.string("buildVersion") else {
                        logicalRuntimeInventorySafe = false
                        continue
                    }

                    logicalRuntimes.append(LogicalRuntime(
                        identifier: identifier,
                        build: build,
                        name: runtime.string("name") ?? identifier,
                        version: runtime.string("version"),
                        platform: runtime.string("platform")))
                }

                if !logicalRuntimeInventorySafe && !hasWarning(.runtime, .completenessFailure) {
                    warnings.append(.completenessFailure(.runtime, String(localized: "Metadati dei runtime logici incompleti.", bundle: .module)))
                }
            } else {
                logicalRuntimeInventorySafe = false
                warnings.append(.completenessFailure(.runtime, String(localized: "Metadati dei runtime logici mancanti o non validi.", bundle: .module)))
            }

            if case .object(let deviceGroups)? = root.property("devices") {
                for group in deviceGroups {
                    guard case .array(let groupDevices) = group.value else {
                        deviceInventorySafe = false
                        continue
                    }

                    for device in groupDevices {
                        let canonicalUuid = device.string("udid").flatMap(XcodeUuid.canonicalExact)
                        let name = device.string("name")
                        let state = device.string("state")
                        guard let canonicalUuid, let name else {
                            deviceInventorySafe = false
                            continue
                        }

                        let blockReason = deviceBlockReason(state)
                        if state == nil || (!XcodeClassifier.isRunning(state) && !XcodeClassifier.isShutdown(state) && !XcodeClassifier.isUnavailable(state)) {
                            deviceInventorySafe = false
                        }

                        let size = device.optionalInt64("dataPathSize")
                        if size.malformed && !hasWarning(.device, .advisory) {
                            warnings.append(.advisory(.device, String(localized: "La dimensione di un dispositivo non è leggibile e resta sconosciuta.", bundle: .module)))
                        }

                        devices.append(XcodeCandidate(
                            key: canonicalUuid,
                            kind: .device,
                            name: name,
                            cliId: canonicalUuid,
                            runtimeIdentifier: group.name,
                            state: state,
                            sizeBytes: size.value,
                            blockReason: blockReason))
                    }
                }
            } else {
                deviceInventorySafe = false
                warnings.append(.completenessFailure(.device, String(localized: "Elenco dispositivi mancante o non valido.", bundle: .module)))
            }
        }

        if !deviceInventorySafe && !hasWarning(.device, .completenessFailure) {
            warnings.append(.completenessFailure(.device, String(localized: "Inventario simulatori incompleto; la rimozione dei simulatori e dei runtime è disabilitata.", bundle: .module)))
        }

        // Raggruppamento per UUID senza distinzione fra maiuscole e minuscole, nell'ordine della
        // prima occorrenza, come GroupBy(…, OrdinalIgnoreCase).
        var groupOrder: [[UInt8]] = []
        var groups: [[UInt8]: [XcodeCandidate]] = [:]
        for device in devices {
            let key = XcodeText.caseInsensitiveKey(device.key)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(device)
        }

        var uniqueDevices: [XcodeCandidate] = []
        for key in groupOrder {
            guard let sameUuid = groups[key], var first = sameUuid.first else { continue }
            let conflicts = sameUuid.dropFirst().contains { other in
                !XcodeText.same(other.name, first.name)
                    || !XcodeText.same(other.runtimeIdentifier, first.runtimeIdentifier)
                    || !XcodeText.same(other.state, first.state)
                    || other.sizeBytes != first.sizeBytes
            }

            if conflicts {
                for runtimeIdentifier in sameUuid.compactMap(\.runtimeIdentifier) {
                    conflictingDeviceRuntimes.insert(XcodeText.ordinalKey(runtimeIdentifier))
                }

                first.sizeBytes = nil
                first.blockReason = String(localized: "UUID dispositivo ripetuto con metadati in conflitto; ripeti l'analisi prima di rimuoverlo.", bundle: .module)
                warnings.append(.completenessFailure(.device, String(localized: "UUID dispositivo ripetuto con metadati in conflitto: \(first.key).", bundle: .module)))
            }

            uniqueDevices.append(first)
        }

        devices = uniqueDevices

        if !deviceInventorySafe {
            devices = devices.map { device in
                var blocked = device
                blocked.blockReason = device.blockReason
                    ?? String(localized: "Inventario simulatori incompleto; ripeti l'analisi prima di rimuovere simulatori.", bundle: .module)
                return blocked
            }
        }

        candidates.append(contentsOf: devices)

        var images: [RuntimeImage] = []
        do {
            let document = try XcodeJsonReader.parse(runtimeJson ?? "")
            guard case .object(let properties) = document else {
                throw StructureError(description: String(localized: "Il JSON delle immagini runtime non è un oggetto.", bundle: .module))
            }

            for property in properties {
                let image = property.value
                let id = image.string("identifier") ?? property.name
                let runtimeIdentifier = image.string("runtimeIdentifier")
                let build = image.string("build")
                let canonicalId = XcodeUuid.canonicalExact(id)

                if canonicalId == nil || runtimeIdentifier == nil || build == nil {
                    runtimeInventorySafe = false
                }

                images.append(RuntimeImage(
                    id: canonicalId ?? id,
                    cliId: canonicalId,
                    runtimeIdentifier: runtimeIdentifier,
                    build: build,
                    version: image.string("version"),
                    state: image.string("state"),
                    backingPath: image.string("path") ?? image.string("diskImagePath"),
                    deletable: image.bool("deletable")))
            }
        } catch {
            runtimeInventorySafe = false
            warnings.append(.completenessFailure(.runtime, String(localized: "Inventario immagini runtime non leggibile: \(XcodeText.message(error))", bundle: .module)))
        }

        if !runtimeInventorySafe && !hasWarning(.runtime, .completenessFailure) {
            warnings.append(.completenessFailure(.runtime, String(localized: "Alcune immagini runtime non hanno identificatori verificabili.", bundle: .module)))
        }

        for image in images {
            var blockReason: String?
            // In C# l'identificatore del runtime veniva nascosto quando il motivo conteneva
            // "ambigua": sono esattamente i due rami che impostano questo indicatore.
            var ambiguous = false
            let exactMatches: [LogicalRuntime] = image.runtimeIdentifier == nil || image.build == nil
                ? []
                : logicalRuntimes.filter { XcodeText.same($0.identifier, image.runtimeIdentifier) && XcodeText.same($0.build, image.build) }

            if image.cliId == nil {
                blockReason = String(localized: "UUID di rimozione non disponibile.", bundle: .module)
            } else if !runtimeDeleteSupported {
                blockReason = String(localized: "Questa versione di Xcode non espone la rimozione dei runtime; gestiscili in Xcode Settings.", bundle: .module)
            } else if !runtimeInventorySafe {
                blockReason = String(localized: "Inventario immagini runtime incompleto; ripeti l'analisi.", bundle: .module)
            } else if !deviceInventorySafe {
                blockReason = String(localized: "Inventario simulatori incompleto; non è possibile verificare l'uso del runtime.", bundle: .module)
            } else if !logicalRuntimeInventorySafe {
                blockReason = String(localized: "Metadati dei runtime logici incompleti; ripeti l'analisi.", bundle: .module)
            } else if let runtimeIdentifier = image.runtimeIdentifier, conflictingDeviceRuntimes.contains(XcodeText.ordinalKey(runtimeIdentifier)) {
                blockReason = String(localized: "Dipendenza non verificabile: un UUID dispositivo ripetuto ha metadati in conflitto.", bundle: .module)
            } else if image.runtimeIdentifier == nil || image.build == nil || exactMatches.count != 1 {
                blockReason = String(localized: "Associazione tra runtime e build ambigua o non verificabile.", bundle: .module)
                ambiguous = true
            } else if image.deletable == false {
                blockReason = String(localized: "Xcode segnala che questa immagine runtime non è rimovibile.", bundle: .module)
            } else if images.filter({ XcodeText.same($0.runtimeIdentifier, image.runtimeIdentifier) && XcodeText.same($0.version, image.version) }).count > 1
                || logicalRuntimes.filter({ XcodeText.same($0.identifier, image.runtimeIdentifier) && XcodeText.same($0.version, image.version) }).count > 1 {
                blockReason = String(localized: "Associazione runtime ambigua: più immagini hanno la stessa versione e le dipendenze dei simulatori non sono distinguibili con certezza.", bundle: .module)
                ambiguous = true
                if !hasWarning(.runtime, .completenessFailure) {
                    warnings.append(.completenessFailure(.runtime, String(localized: "Associazione runtime/build ambigua: immagini con la stessa versione hanno build diverse.", bundle: .module)))
                }
            }

            let dependentDevices: [XcodeCandidate] = image.runtimeIdentifier == nil
                ? []
                : devices.filter { XcodeText.same($0.runtimeIdentifier, image.runtimeIdentifier) }
            if blockReason == nil && dependentDevices.contains(where: { XcodeClassifier.isRunning($0.state) }) {
                blockReason = String(localized: "Un dispositivo che usa questo runtime è avviato; arrestalo in Xcode prima di rimuoverlo.", bundle: .module)
            } else if blockReason == nil && dependentDevices.contains(where: { !XcodeClassifier.isShutdown($0.state) && !XcodeClassifier.isUnavailable($0.state) }) {
                blockReason = String(localized: "Lo stato di un dispositivo che usa questo runtime non è verificato.", bundle: .module)
            }

            let runtimeName: String
            if exactMatches.count == 1, let match = exactMatches.first {
                runtimeName = match.name
            } else {
                let identifier = image.runtimeIdentifier ?? String(localized: "Runtime sconosciuto", bundle: .module)
                runtimeName = XcodeText.trimmed("\(identifier) \(image.version ?? image.build ?? "")")
            }

            candidates.append(XcodeCandidate(
                key: "runtime:\(image.cliId ?? image.id)",
                kind: .runtime,
                name: runtimeName,
                path: image.backingPath,
                cliId: image.cliId,
                runtimeIdentifier: ambiguous ? nil : image.runtimeIdentifier,
                build: image.build,
                state: image.state,
                // Il sizeBytes della CLI è una stima logica dell'immagine: i byte allocati si
                // misurano a parte, sul percorso dell'immagine che la CLI riporta.
                sizeBytes: nil,
                blockReason: blockReason,
                dependencies: dependentDevices.map(\.key)))
        }

        return XcodeSnapshot(candidates: candidates, warnings: warnings)
    }

    /// Il motivo di blocco di un dispositivo appena letto: nessuno se spento.
    private static func deviceBlockReason(_ state: String?) -> String? {
        if XcodeClassifier.isShutdown(state) { return nil }
        if XcodeClassifier.isRunning(state) {
            return String(localized: "Arresta il dispositivo in Xcode prima di rimuoverlo.", bundle: .module)
        }
        guard let state else {
            return String(localized: "Stato del dispositivo non verificato; ripeti l'analisi.", bundle: .module)
        }
        return String(localized: "Stato del dispositivo non verificato: \(state); ripeti l'analisi.", bundle: .module)
    }
}
