public struct CleanupCategory: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String
    public let risk: RiskLevel
    public let selectedByDefault: Bool
    public let parentId: String?
    public let rules: [CleanupRule]

    public init(
        id: String,
        displayName: String,
        description: String,
        risk: RiskLevel,
        selectedByDefault: Bool,
        parentId: String?,
        rules: [CleanupRule]
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.risk = risk
        self.selectedByDefault = selectedByDefault
        self.parentId = parentId
        self.rules = rules
    }
}
