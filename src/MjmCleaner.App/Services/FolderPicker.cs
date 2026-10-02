using Avalonia.Controls;
using Avalonia.Platform.Storage;

namespace MjmCleaner.App.Services;

public interface IFolderPicker
{
    /// <summary>Percorso locale della cartella scelta, o <c>null</c> se l'utente annulla.</summary>
    Task<string?> PickFolderAsync(string title);
}

/// <summary>Pannello nativo di scelta cartella, agganciato alla finestra indicata.</summary>
public sealed class StorageFolderPicker(TopLevel topLevel) : IFolderPicker
{
    public async Task<string?> PickFolderAsync(string title)
    {
        IReadOnlyList<IStorageFolder> folders = await topLevel.StorageProvider.OpenFolderPickerAsync(
            new FolderPickerOpenOptions { Title = title, AllowMultiple = false });
        return folders.Count == 0 ? null : folders[0].TryGetLocalPath();
    }
}
