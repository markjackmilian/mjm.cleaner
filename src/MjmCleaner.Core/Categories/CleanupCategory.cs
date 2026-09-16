namespace MjmCleaner.Core.Categories;

public sealed record CleanupCategory(
    string Id,
    string DisplayName,
    string Description,
    RiskLevel Risk,
    bool SelectedByDefault,
    string? ParentId,
    IReadOnlyList<CleanupRule> Rules);
