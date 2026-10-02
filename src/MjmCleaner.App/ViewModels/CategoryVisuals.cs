namespace MjmCleaner.App.ViewModels;

public sealed record CategoryVisual(string TileColor, string IconData);

/// <summary>Tile colorata e glifo per categoria, come nel redesign; ID sconosciuti ricevono la tile neutra.</summary>
public static class CategoryVisuals
{
    private const string Drive = "M5.5 7 H18.5 A2.5 2.5 0 0 1 21 9.5 V14.5 A2.5 2.5 0 0 1 18.5 17 H5.5 A2.5 2.5 0 0 1 3 14.5 V9.5 A2.5 2.5 0 0 1 5.5 7 Z M7 12 H12 M15.9 12 A0.6 0.6 0 1 0 17.1 12 A0.6 0.6 0 1 0 15.9 12 Z";
    private const string Code = "M8 8 L4 12 L8 16 M16 8 L20 12 L16 16 M13.5 6 L10.5 18";
    private const string Cube = "M12 3 L20 7.5 V16.5 L12 21 L4 16.5 V7.5 Z M4 7.5 L12 12 L20 7.5 M12 12 V21";
    private const string Folder = "M3.5 7.5 A2 2 0 0 1 5.5 5.5 H9.3 L11.3 7.5 H18.5 A2 2 0 0 1 20.5 9.5 V16.5 A2 2 0 0 1 18.5 18.5 H5.5 A2 2 0 0 1 3.5 16.5 Z";
    private const string Document = "M7 3.5 H14 L18 7.5 V20.5 H7 Z M14 3.5 V7.5 H18 M10 12 H15 M10 15.5 H15";
    private const string Trash = "M4.5 7 H19.5 M10 7 V4.5 H14 V7 M6.5 7 L7.5 20 H16.5 L17.5 7 M10.5 11 V16 M13.5 11 V16";
    private const string Download = "M12 4 V15 M7.5 10.5 L12 15 L16.5 10.5 M5 19.5 H19";

    public static CategoryVisual For(string categoryId) => categoryId switch
    {
        "system-caches" => new("#66788F", Drive),
        "dev-caches" => new("#7457E8", Code),
        "nuget-packages" => new("#3567D0", Cube),
        "project-build-output" => new("#1D8784", Folder),
        "logs" => new("#85858B", Document),
        "trash" => new("#D2453A", Trash),
        "downloads-large" => new("#E8833A", Download),
        _ => new("#85858B", Document),
    };
}
