using System.IO.Abstractions;
using System.Text.Json;

namespace MjmCleaner.Core.Settings;

public interface ISettingsStore
{
    CleanerSettings Load();
    void Save(CleanerSettings settings);
}

public sealed class SettingsStore(IFileSystem fileSystem, AppPaths paths) : ISettingsStore
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    /// <summary>Preferenze illeggibili o corrotte non devono impedire l'avvio: si torna ai valori predefiniti.</summary>
    public CleanerSettings Load()
    {
        try
        {
            if (!fileSystem.File.Exists(paths.SettingsFile))
            {
                return new CleanerSettings();
            }

            string json = fileSystem.File.ReadAllText(paths.SettingsFile);
            return JsonSerializer.Deserialize<CleanerSettings>(json, Options) ?? new CleanerSettings();
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            return new CleanerSettings();
        }
    }

    public void Save(CleanerSettings settings)
    {
        fileSystem.Directory.CreateDirectory(paths.SupportDirectory);
        fileSystem.File.WriteAllText(
            paths.SettingsFile,
            JsonSerializer.Serialize(settings, Options));
    }
}
