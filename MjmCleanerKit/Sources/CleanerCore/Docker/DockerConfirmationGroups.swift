public enum DockerGroupMode: Sendable, Equatable, Hashable {
    /// Si conferma in blocco con un'unica casella: le voci sicure.
    case block

    /// Si confermano le singole voci, o tutte insieme dal gruppo.
    case selectable

    /// Solo da leggere: le voci KEEP non si possono selezionare.
    case readOnly
}

public struct DockerConfirmationGroup: Sendable, Equatable {
    public let id: String
    public let title: String
    public let description: String
    public let mode: DockerGroupMode
    public let items: [DockerCandidate]

    public init(id: String, title: String, description: String, mode: DockerGroupMode, items: [DockerCandidate]) {
        self.id = id
        self.title = title
        self.description = description
        self.mode = mode
        self.items = items
    }

    public var selectedByDefault: Bool { mode == .block }
}

/// Raggruppa i candidati per la schermata di conferma e ricava la selezione da consegnare
/// all'esecutore. Logica pura nel Core, come `ConfirmationRows` per il wizard: ciò che decide cosa
/// viene cancellato va coperto dai test, non solo esercitato a mano nell'interfaccia.
public enum DockerConfirmationGroups {
    public static let safeId = "safe"
    public static let localBuildsId = "local-builds"
    public static let unusedImagesId = "unused-images"
    public static let unusedVolumesId = "unused-volumes"
    public static let keepId = "keep"

    public static func build(_ candidates: [DockerCandidate]) -> [DockerConfirmationGroup] {
        let groups = [
            DockerConfirmationGroup(
                id: safeId,
                title: String(localized: "Eliminabili in sicurezza", bundle: .module),
                description: String(localized: "Immagini dangling, immagini che Testcontainers e Aspire ricreano da soli, cache di build. Si confermano in blocco.", bundle: .module),
                mode: .block,
                items: candidates.filter { $0.verdict == .delete }),

            DockerConfirmationGroup(
                id: localBuildsId,
                title: String(localized: "Costruite in locale", bundle: .module),
                description: String(localized: "Non si possono riscaricare: dopo la cancellazione vanno ricostruite dal loro Dockerfile.", bundle: .module),
                mode: .selectable,
                items: candidates.filter { $0.verdict == .ask }),

            DockerConfirmationGroup(
                id: unusedImagesId,
                title: String(localized: "Immagini non usate", bundle: .module),
                description: String(localized: "Nessun container le usa. Costo: riscaricarle al prossimo utilizzo.", bundle: .module),
                mode: .selectable,
                items: candidates.filter { $0.verdict == .propose && $0.kind == .image }),

            DockerConfirmationGroup(
                id: unusedVolumesId,
                title: String(localized: "Volumi non montati", bundle: .module),
                description: String(localized: "I volumi contengono dati: cancellarli li perde per sempre. Quelli con nome si confermano uno alla volta.", bundle: .module),
                mode: .selectable,
                items: candidates.filter { $0.verdict == .propose && $0.kind == .volume }),

            DockerConfirmationGroup(
                id: keepId,
                title: String(localized: "Da tenere", bundle: .module),
                description: String(localized: "In uso, citate nei progetti o ricollegate da Aspire al prossimo avvio.", bundle: .module),
                mode: .readOnly,
                items: candidates.filter { $0.verdict == .keep }),
        ]

        return groups.filter { !$0.items.isEmpty }
    }

    /// Un volume con nome che nessuna regola sa ricondurre a un progetto è il caso più rischioso: non
    /// lo seleziona la casella del gruppo, solo la sua.
    public static func requiresIndividualConfirmation(_ candidate: DockerCandidate) -> Bool {
        candidate.kind == .volume && candidate.ruleId == "named-unused"
    }

    /// Le voci da consegnare all'esecutore. I gruppi a blocco contano per intero o per niente; i
    /// gruppi in sola lettura mai; le voci KEEP sono escluse comunque, qualunque cosa dica
    /// l'interfaccia.
    public static func selection(
        _ groups: [DockerConfirmationGroup],
        isGroupSelected: (DockerConfirmationGroup) -> Bool,
        isItemSelected: (DockerCandidate) -> Bool
    ) -> [DockerCandidate] {
        groups
            .flatMap { group -> [DockerCandidate] in
                switch group.mode {
                case .block: isGroupSelected(group) ? group.items : []
                case .selectable: group.items.filter(isItemSelected)
                case .readOnly: []
                }
            }
            .filter { $0.verdict != .keep }
    }
}
