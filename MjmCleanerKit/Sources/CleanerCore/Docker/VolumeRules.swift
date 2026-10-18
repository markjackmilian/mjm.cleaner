public struct VolumeRule: Sendable {
    public let id: String
    public let evaluate: @Sendable (DockerVolume, VolumeRuleContext) -> RuleMatch?

    public init(_ id: String, _ evaluate: @escaping @Sendable (DockerVolume, VolumeRuleContext) -> RuleMatch?) {
        self.id = id
        self.evaluate = evaluate
    }
}

/// Nome di un volume creato da .NET Aspire: `<app>.apphost-<hash>-<risorsa>-data`. L'hash deriva
/// dal percorso dell'AppHost: spostare o rinominare la cartella del progetto produce un hash nuovo,
/// e i volumi con il vecchio restano orfani.
public struct AspireVolumeName: Sendable, Equatable, Hashable {
    public let app: String
    public let hash: String
    public let resource: String

    public init(app: String, hash: String, resource: String) {
        self.app = app
        self.hash = hash
        self.resource = resource
    }

    public static func tryParse(_ volumeName: String) -> AspireVolumeName? {
        // `^(?<app>.+?)\.apphost-(?<hash>[0-9a-f]{6,64})-(?<resource>.+)-data$` di .NET: il "." di
        // .NET esclude solo "\n" (quello di Swift anche "\r" e U+2028) e il suo "$" accetta un "\n"
        // finale (quello di Swift no).
        let pattern = /^(?<app>[^\n]+?)\.apphost-(?<hash>[0-9a-f]{6,64})-(?<resource>[^\n]+)-data\n?$/
            .matchingSemantics(.unicodeScalar)
        guard let match = volumeName.firstMatch(of: pattern) else { return nil }
        return AspireVolumeName(app: String(match.output.app), hash: String(match.output.hash), resource: String(match.output.resource))
    }
}

public struct VolumeRuleContext: Sendable {
    public static let composeProjectLabel = "com.docker.compose.project"

    public let mountedBy: [String: [DockerContainer]]
    public let composeProjects: Set<String>
    public let aspireHashesInUse: [String: Set<String>]

    public init(snapshot: DockerSnapshot, references: ProjectReferences) {
        var mounted: [String: [DockerContainer]] = [:]
        for container in snapshot.containers {
            for volume in container.volumeNames {
                mounted[volume, default: []].append(container)
            }
        }
        mountedBy = mounted

        composeProjects = snapshot.existingComposeProjects.union(references.composeProjects)

        // Un hash è "in uso" per un'app quando un suo volume è montato da un container, anche
        // fermo: Aspire lo ricollegherà al prossimo avvio insieme agli altri volumi con lo stesso hash.
        var hashes: [String: Set<String>] = [:]
        for name in mounted.keys.compactMap(AspireVolumeName.tryParse) {
            hashes[name.app, default: []].insert(name.hash)
        }
        aspireHashesInUse = hashes
    }
}

/// Regole sui volumi in ordine di priorità. Un volume contiene dati: nessuna regola produce DELETE,
/// e nel dubbio si tiene.
public enum VolumeRules {
    private static var dataLost: String { String(localized: "dati persi", bundle: .module) }

    public static let `default`: [VolumeRule] = [
        VolumeRule("mounted") { volume, context in
            guard let users = context.mountedBy[volume.name] else { return nil }
            return RuleMatch(
                verdict: .keep,
                reason: String(localized: "montato da \(ImageRules.describeContainers(users))", bundle: .module),
                cost: "")
        },

        VolumeRule("anonymous") { volume, _ in
            guard isAnonymous(volume.name) else { return nil }
            return RuleMatch(
                verdict: .propose,
                reason: String(localized: "volume anonimo non montato", bundle: .module),
                cost: dataLost)
        },

        VolumeRule("compose-project") { volume, context in
            guard let project = volume.labels[VolumeRuleContext.composeProjectLabel],
                  context.composeProjects.contains(project) else { return nil }
            return RuleMatch(
                verdict: .keep,
                reason: String(localized: "progetto compose «\(project)» ancora presente", bundle: .module),
                cost: "")
        },

        VolumeRule("aspire-current") { volume, context in
            guard let name = AspireVolumeName.tryParse(volume.name),
                  let hashes = context.aspireHashesInUse[name.app],
                  hashes.contains(name.hash) else { return nil }
            return RuleMatch(
                verdict: .keep,
                reason: String(localized: "AppHost «\(name.app)» in uso con lo stesso hash: Aspire lo ricollega al prossimo avvio", bundle: .module),
                cost: "")
        },

        VolumeRule("aspire-stale") { volume, context in
            guard let name = AspireVolumeName.tryParse(volume.name),
                  let hashes = context.aspireHashesInUse[name.app] else { return nil }
            let inUse = DockerText.ordinalSorted(hashes).joined(separator: ", ")
            return RuleMatch(
                verdict: .propose,
                reason: String(localized: "hash AppHost vecchio (in uso: \(inUse))", bundle: .module),
                cost: dataLost)
        },

        VolumeRule("named-unused") { _, _ in
            RuleMatch(
                verdict: .propose,
                reason: String(localized: "volume con nome non montato: va confermato esplicitamente", bundle: .module),
                cost: dataLost)
        },
    ]

    /// `^[0-9a-f]{64}$` di .NET, il cui "$" accetta un "\n" finale.
    private static func isAnonymous(_ name: String) -> Bool {
        name.firstMatch(of: /^[0-9a-f]{64}\n?$/.matchingSemantics(.unicodeScalar)) != nil
    }
}
