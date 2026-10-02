using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.App.ViewModels;

/// <summary>
/// Nomi leggibili per gli identificativi salvati nello storico: il catalogo corrente,
/// le categorie di Docker e Xcode e gli ID di versioni precedenti del catalogo.
/// </summary>
public static class CategoryNames
{
    private static readonly Dictionary<string, string> Fixed = new(StringComparer.Ordinal)
    {
        [DockerCategories.Images] = "Immagini Docker",
        [DockerCategories.Volumes] = "Volumi Docker",
        [DockerCategories.BuildCache] = "Cache di build Docker",
        ["xcode-derived-data"] = "DerivedData",
        ["xcode-device-support"] = "Device Support",
        ["xcode-simulator-devices"] = "Dispositivi simulati",
        ["xcode-runtimes"] = "Runtime dei simulatori",
        ["trash-downloads-large"] = "Cestino, Download e file grandi",
    };

    public static IReadOnlyDictionary<string, string> Build(IEnumerable<CleanupCategory> catalog)
    {
        Dictionary<string, string> names = new(Fixed, StringComparer.Ordinal);
        foreach (CleanupCategory category in catalog) names[category.Id] = category.DisplayName;
        return names;
    }
}
