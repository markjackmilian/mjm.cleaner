import Foundation

/// Un elenco di regole personalizzato senza una regola finale che si applica sempre: è un errore di
/// programmazione, non di dati. Porting della `InvalidOperationException` di `FirstMatch`.
public struct DockerRuleError: Error, Equatable, Sendable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Classificazione pura: stesso snapshot, stessi riferimenti, stesso risultato. Nessuna chiamata a
/// Docker né al disco — è ciò che permette di verificarla con le sole fixture JSON.
public enum DockerClassifier {
    public static let buildCacheId = "build-cache"

    public static func classify(_ snapshot: DockerSnapshot, _ references: ProjectReferences) throws -> [DockerCandidate] {
        try classify(snapshot, references, imageRules: ImageRules.default, volumeRules: VolumeRules.default)
    }

    public static func classify(
        _ snapshot: DockerSnapshot,
        _ references: ProjectReferences,
        imageRules: [ImageRule],
        volumeRules: [VolumeRule]
    ) throws -> [DockerCandidate] {
        let imageContext = ImageRuleContext(snapshot: snapshot, references: references)
        let volumeContext = VolumeRuleContext(snapshot: snapshot, references: references)
        var candidates: [DockerCandidate] = []

        for image in snapshot.images {
            let (ruleId, match) = try firstMatch(imageRules.lazy.map { ($0.id, $0.evaluate(image, imageContext)) })
            candidates.append(DockerCandidate(
                kind: .image,
                id: image.id,
                displayName: image.displayName,
                sizeBytes: image.sizeBytes,
                verdict: match.verdict,
                ruleId: ruleId,
                reason: withPossibleReference(match, image, references),
                cost: match.cost))
        }

        for volume in snapshot.volumes {
            let (ruleId, match) = try firstMatch(volumeRules.lazy.map { ($0.id, $0.evaluate(volume, volumeContext)) })
            candidates.append(DockerCandidate(
                kind: .volume,
                id: volume.name,
                displayName: volume.name,
                sizeBytes: volume.sizeBytes,
                verdict: match.verdict,
                ruleId: ruleId,
                reason: match.reason,
                cost: match.cost))
        }

        if snapshot.df.buildCache > 0 {
            // La parte condivisa con immagini ancora presenti non si libera finché quelle restano:
            // la dimensione mostrata è un massimo, non una promessa.
            let cache = snapshot.df.entries.first { $0.type == DockerDfSummary.buildCacheType }
            let reason = if let cache, cache.reclaimableBytes < cache.sizeBytes {
                String(localized: "cache di BuildKit, in parte condivisa con immagini presenti: si libera del tutto solo se anche quelle vengono eliminate", bundle: .module)
            } else {
                String(localized: "cache di BuildKit", bundle: .module)
            }

            candidates.append(DockerCandidate(
                kind: .buildCache,
                id: buildCacheId,
                displayName: String(localized: "Cache di build", bundle: .module),
                sizeBytes: snapshot.df.buildCache,
                verdict: .delete,
                ruleId: buildCacheId,
                reason: reason,
                cost: String(localized: "solo tempo alla build successiva", bundle: .module)))
        }

        return candidates
    }

    /// La prima regola che si applica, valutando le successive solo se serve (come il `foreach` del C#).
    private static func firstMatch(_ evaluations: some Sequence<(String, RuleMatch?)>) throws -> (String, RuleMatch) {
        for (id, match) in evaluations {
            if let match {
                return (id, match)
            }
        }

        // Ogni elenco termina con una regola che si applica sempre: arrivare qui vuol dire che un
        // elenco personalizzato l'ha omessa, ed è un errore di programmazione, non di dati.
        throw DockerRuleError(String(localized: "Nessuna regola si applica: l'ultima regola dell'elenco deve applicarsi sempre.", bundle: .module))
    }

    /// Un file che cita il repository senza tag ("AddKeycloak()") non basta a tenere un'immagine —
    /// terrebbe ogni versione del repository — ma l'utente deve saperlo prima di decidere.
    private static func withPossibleReference(_ match: RuleMatch, _ image: DockerImage, _ references: ProjectReferences) -> String {
        guard match.verdict == .propose || match.verdict == .ask else { return match.reason }

        let names = image.names
        guard let possible = references.images.first(where: { reference in
            reference.tag == nil && names.contains { $0.repository == reference.repository }
        }) else {
            return match.reason
        }

        return String(localized: "\(match.reason) · possibile riferimento in \(possible.file):\(String(possible.line))", bundle: .module)
    }
}
