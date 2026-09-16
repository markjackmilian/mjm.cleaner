namespace MjmCleaner.Core.Categories;

public enum ScanMode
{
    /// <summary>Svuota il contenuto della root mantenendo la root stessa.</summary>
    ClearContents,

    /// <summary>Cerca ricorsivamente directory il cui nome corrisponde ai pattern.</summary>
    MatchingDirs,

    /// <summary>Cerca file per pattern, età e dimensione.</summary>
    MatchingFiles,
}

public enum RiskLevel { Low, Medium, High }

public sealed record CleanupRule(
    string Root,
    ScanMode Mode,
    string[] IncludeGlobs,
    string[] ExcludeGlobs,
    TimeSpan? MinAge = null,
    long? MinSizeBytes = null,
    int MaxDepth = int.MaxValue,
    bool RequiresProjectMarker = false);
