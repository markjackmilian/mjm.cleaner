/// Esito di una regola che si applica: verdetto, motivo mostrato all'utente e costo per ricreare
/// la risorsa.
public struct RuleMatch: Sendable, Equatable {
    public let verdict: DockerVerdict
    public let reason: String
    public let cost: String

    public init(verdict: DockerVerdict, reason: String, cost: String) {
        self.verdict = verdict
        self.reason = reason
        self.cost = cost
    }
}

/// Una regola: restituisce `nil` quando non si applica, e la valutazione passa alla successiva.
public struct ImageRule: Sendable {
    public let id: String
    public let evaluate: @Sendable (DockerImage, ImageRuleContext) -> RuleMatch?

    public init(_ id: String, _ evaluate: @escaping @Sendable (DockerImage, ImageRuleContext) -> RuleMatch?) {
        self.id = id
        self.evaluate = evaluate
    }
}

/// Fatti ricavati una sola volta dallo snapshot e condivisi da tutte le regole sulle immagini.
public struct ImageRuleContext: Sendable {
    public static let aspireBaseImageLabel = "com.microsoft.developer.usvc-dev.base-image-digest"
    public static let testcontainersLabel = "org.testcontainers"

    public let references: ProjectReferences

    /// Container (anche fermi) per ID COMPLETO dell'immagine: mai per tag.
    public let usersByImageId: [String: [DockerContainer]]

    public let inUseTagsByRepository: [String: Set<String>]

    /// Digest dell'immagine base → nome dell'immagine dello strumento che la dichiara.
    public let toolBaseImages: [String: String]

    public init(snapshot: DockerSnapshot, references: ProjectReferences) {
        self.references = references

        let users = Dictionary(grouping: snapshot.containers, by: \.imageId)
        usersByImageId = users

        var inUseTags: [String: Set<String>] = [:]
        for image in snapshot.images where users[image.id] != nil {
            for name in image.names {
                if let tag = name.tag {
                    inUseTags[name.repository, default: []].insert(tag)
                }
            }
        }
        inUseTagsByRepository = inUseTags

        // Le immagini base dichiarate dagli strumenti (il tunnel dcptun di Aspire indica la sua in
        // un'etichetta): lo strumento le riscarica da solo quando ricostruisce la derivata.
        var toolBases: [String: String] = [:]
        for tool in snapshot.images where Self.isCreatedByTool(tool) {
            if let digest = tool.labels[Self.aspireBaseImageLabel], toolBases[digest] == nil {
                toolBases[digest] = tool.displayName
            }
        }
        toolBaseImages = toolBases
    }

    public static func isCreatedByTool(_ image: DockerImage) -> Bool {
        image.labels[testcontainersLabel] == "true"
            || image.names.contains { name in
                DockerText.hasSuffix(name.repository, "/testcontainers/ryuk")
                    || DockerText.hasPrefix(name.shortName, "dcptun_")
            }
    }

    /// L'etichetta dello strumento contiene un digest: con il containerd store coincide con l'ID,
    /// con lo store classico è quello del manifest, che compare in `RepoDigests`.
    public func toolDeclaringAsBase(_ image: DockerImage) -> String? {
        if let tool = toolBaseImages[image.id] {
            return tool
        }

        for repoDigest in image.repoDigests {
            let bytes = Array(repoDigest.utf8)
            if let at = bytes.firstIndex(of: UInt8(ascii: "@")),
               let tool = toolBaseImages[String(decoding: bytes.suffix(from: at + 1), as: UTF8.self)] {
                return tool
            }
        }

        return nil
    }
}

/// Regole sulle immagini in ordine di priorità: vince la prima che si applica. Per aggiungere un
/// caso si aggiunge una riga, nel punto giusto dell'elenco.
public enum ImageRules {
    private static var redownload: String { String(localized: "riscaricare", bundle: .module) }

    public static let `default`: [ImageRule] = [
        ImageRule("in-use") { image, context in
            guard let users = context.usersByImageId[image.id] else { return nil }
            return RuleMatch(
                verdict: .keep,
                reason: String(localized: "usata da \(describeContainers(users))", bundle: .module),
                cost: "")
        },

        ImageRule("dangling") { image, _ in
            guard image.isDangling else { return nil }
            return RuleMatch(
                verdict: .delete,
                reason: String(localized: "immagine dangling, senza tag", bundle: .module),
                cost: String(localized: "nessuno", bundle: .module))
        },

        // Prima di "locally-built": il tunnel dcptun è costruito in locale da Aspire, ma è Aspire a
        // ricostruirlo al prossimo avvio — "non si può riscaricare" non è un costo per l'utente.
        ImageRule("tool-recreated") { image, context in
            if image.labels[ImageRuleContext.testcontainersLabel] == "true"
                || image.names.contains(where: { DockerText.hasSuffix($0.repository, "/testcontainers/ryuk") }) {
                return RuleMatch(
                    verdict: .delete,
                    reason: String(localized: "ricreata automaticamente da Testcontainers", bundle: .module),
                    cost: String(localized: "nessuno: la riscarica Testcontainers", bundle: .module))
            }

            if image.names.contains(where: { DockerText.hasPrefix($0.shortName, "dcptun_") }) {
                return RuleMatch(
                    verdict: .delete,
                    reason: String(localized: "tunnel di .NET Aspire, ricreato a ogni avvio", bundle: .module),
                    cost: String(localized: "nessuno: la ricostruisce Aspire", bundle: .module))
            }

            guard let tool = context.toolDeclaringAsBase(image) else { return nil }
            return RuleMatch(
                verdict: .delete,
                reason: String(localized: "immagine base di \(tool)", bundle: .module),
                cost: String(localized: "nessuno: la riscarica lo strumento", bundle: .module))
        },

        ImageRule("locally-built") { image, _ in
            guard isLocallyBuilt(image) else { return nil }
            return RuleMatch(
                verdict: .ask,
                reason: String(localized: "costruita in locale: non si può riscaricare", bundle: .module),
                cost: String(localized: "ricostruire dal Dockerfile", bundle: .module))
        },

        ImageRule("referenced") { image, context in
            guard let reference = exactReference(image, context) else { return nil }
            return RuleMatch(
                verdict: .keep,
                reason: String(localized: "citata in \(reference.file):\(String(reference.line))", bundle: .module),
                cost: "")
        },

        ImageRule("superseded") { image, context in
            for name in image.names {
                if let tags = context.inUseTagsByRepository[name.repository], tags.contains(where: { $0 != name.tag }) {
                    let inUse = DockerText.ordinalSorted(tags).joined(separator: ", ")
                    return RuleMatch(
                        verdict: .propose,
                        reason: String(localized: "versione superata: in uso \(inUse)", bundle: .module),
                        cost: redownload)
                }
            }

            return nil
        },

        ImageRule("unused") { _, _ in
            RuleMatch(
                verdict: .propose,
                reason: String(localized: "non usata da alcun container", bundle: .module),
                cost: redownload)
        },
    ]

    /// Con `Identity` (Docker 29, containerd store) l'origine è esplicita; senza, ricade sul
    /// criterio dello store classico: nessun digest di registro.
    private static func isLocallyBuilt(_ image: DockerImage) -> Bool {
        switch image.origin {
        case .built: true
        case .pulled: false
        case .unknown: image.repoDigests.isEmpty
        }
    }

    private static func exactReference(_ image: DockerImage, _ context: ImageRuleContext) -> ImageReference? {
        context.references.images.first { reference in
            reference.tag != nil
                && image.names.contains { $0.repository == reference.repository && $0.tag == reference.tag }
        }
    }

    static func describeContainers(_ containers: [DockerContainer]) -> String {
        containers.map { container in
            let state = container.state == "running"
                ? String(localized: "in esecuzione", bundle: .module)
                : String(localized: "fermo", bundle: .module)
            return "\(container.name) (\(state))"
        }.joined(separator: ", ")
    }
}
