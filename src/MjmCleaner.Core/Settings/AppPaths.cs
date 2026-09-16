namespace MjmCleaner.Core.Settings;

/// <summary>
/// I dati dell'applicazione vivono sotto Application Support, che la deny-list
/// protegge: l'applicazione non può eliminare il proprio storico.
/// </summary>
public sealed class AppPaths(string homeDirectory)
{
    public string SupportDirectory { get; } =
        Path.Combine(homeDirectory, "Library", "Application Support", "mjm.cleaner");

    public string DatabaseFile => Path.Combine(SupportDirectory, "history.db");
    public string SettingsFile => Path.Combine(SupportDirectory, "settings.json");
    public string LogsDirectory => Path.Combine(SupportDirectory, "logs");

    public static AppPaths ForCurrentUser()
        => new(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
}
