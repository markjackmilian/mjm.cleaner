using MjmCleaner.App.Services;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App.Tests;

/// <summary>Home temporanea per i test che usano il vero <see cref="AppServices"/>: tutto ciò che scrive sta sotto di essa e sparisce con Dispose.</summary>
internal sealed class TestHome : IDisposable
{
    private TestHome(string path, AppServices services)
    {
        Path = path;
        Services = services;
    }

    public string Path { get; }
    public AppServices Services { get; }

    public static async Task<TestHome> CreateAsync(CleanerSettings? settings = null)
    {
        string home = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "mjm-cleaner-tests-" + Guid.NewGuid().ToString("N"));
        AppServices services = await AppServices.CreateAsync(new AppPaths(home));
        if (settings is not null) services.Settings.Save(settings);
        return new TestHome(home, services);
    }

    public void Dispose()
    {
        try
        {
            if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true);
        }
        catch (IOException)
        {
            // Best effort: il database SQLite può restare aperto fino alla chiusura del processo di test.
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
