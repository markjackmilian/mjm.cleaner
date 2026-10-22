public struct CleanupCategory: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String
    public let risk: RiskLevel
    public let selectedByDefault: Bool
    public let parentId: String?
    public let rules: [CleanupRule]
    /// Lo stato iniziale delle voci al passo 3: falso per le categorie di dati reali (Download, File
    /// grandi), dove ogni voce va spuntata a mano.
    public let itemsSelectedByDefault: Bool

    public init(
        id: String,
        displayName: String,
        description: String,
        risk: RiskLevel,
        selectedByDefault: Bool,
        parentId: String?,
        rules: [CleanupRule],
        itemsSelectedByDefault: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.risk = risk
        self.selectedByDefault = selectedByDefault
        self.parentId = parentId
        self.rules = rules
        self.itemsSelectedByDefault = itemsSelectedByDefault
    }

    /// La stessa categoria con le cartelle escluse nelle Impostazioni su ogni regola.
    public func excluding(_ excludedPaths: [String]) -> CleanupCategory {
        CleanupCategory(
            id: id, displayName: displayName, description: description, risk: risk, selectedByDefault: selectedByDefault,
            parentId: parentId, rules: rules.map { $0.excluding(excludedPaths) }, itemsSelectedByDefault: itemsSelectedByDefault)
    }

    /// La categoria Download per un'analisi completa, senza il solo filtro di età.
    public func forCompleteDownloads() -> CleanupCategory {
        guard id == "downloads" else { return self }
        return CleanupCategory(
            id: id, displayName: displayName, description: description, risk: risk, selectedByDefault: selectedByDefault,
            parentId: parentId, rules: rules.map { $0.withoutMinimumAge().pruningEmptyDirectories() }, itemsSelectedByDefault: true)
    }
}
