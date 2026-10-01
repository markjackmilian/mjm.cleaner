using System.ComponentModel;
using System.IO.Abstractions;

namespace MjmCleaner.Core.Docker;

/// <summary>
/// Docker non raggiungibile: binario assente, daemon spento, socket chiuso. Il messaggio è già
/// pensato per l'utente — l'interfaccia lo mostra così com'è, senza stack trace.
/// </summary>
public sealed class DockerUnavailableException(string message, Exception? inner = null) : Exception(message, inner)
{
    public const string NotRunning = "Docker non è in esecuzione. Avvia Docker Desktop e premi Riprova.";
    public const string NotInstalled = "Docker non è installato o non è stato trovato.";
}

/// <summary>Un comando Docker è fallito: il messaggio riporta il testo d'errore della CLI.</summary>
public sealed class DockerCommandException(string message) : Exception(message);

public interface IDockerCli
{
    Task<ProcessResult> RunAsync(IReadOnlyList<string> args, CancellationToken ct, TimeSpan? timeout = null);
}

public static class DockerCliErrors
{
    // Messaggi misurati sulle CLI 24–29: il testo cambia fra le versioni, il socket irraggiungibile no.
    private static readonly string[] DaemonUnavailableMarkers =
    [
        "Cannot connect to the Docker daemon",
        "Is the docker daemon running",
        "error during connect",
        "failed to connect to the docker API",
        "docker.sock: connect:",
    ];

    public static bool IsDaemonUnavailable(string stderr)
        => DaemonUnavailableMarkers.Any(marker => stderr.Contains(marker, StringComparison.OrdinalIgnoreCase));

    /// <summary>La prima riga utile dell'errore della CLI, senza il prefisso ripetuto dal daemon.</summary>
    public static string Describe(ProcessResult result)
    {
        if (result.TimedOut)
        {
            return "Docker non ha risposto entro il tempo massimo";
        }

        string line = result.StdErr
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .FirstOrDefault() ?? $"codice di uscita {result.ExitCode}";

        const string Prefix = "Error response from daemon: ";
        return line.StartsWith(Prefix, StringComparison.Ordinal) ? line[Prefix.Length..] : line;
    }

    /// <summary>Esegue e restituisce lo stdout; qualunque uscita diversa da zero diventa un'eccezione leggibile.</summary>
    public static async Task<string> RunCheckedAsync(this IDockerCli cli, IReadOnlyList<string> args, CancellationToken ct)
    {
        ProcessResult result = await cli.RunAsync(args, ct);

        if (result.TimedOut || result.ExitCode != 0)
        {
            throw new DockerCommandException($"docker {string.Join(' ', args.Take(2))}: {Describe(result)}");
        }

        return result.StdOut;
    }
}

/// <summary>Unico punto dell'applicazione che esegue il binario <c>docker</c>.</summary>
public sealed class DockerCli(IProcessRunner runner, string? binaryPath) : IDockerCli
{
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(60);

    public async Task<ProcessResult> RunAsync(IReadOnlyList<string> args, CancellationToken ct, TimeSpan? timeout = null)
    {
        if (binaryPath is null)
        {
            throw new DockerUnavailableException(DockerUnavailableException.NotInstalled);
        }

        ProcessResult result;
        try
        {
            result = await runner.RunAsync(binaryPath, args, timeout ?? DefaultTimeout, ct, Environment(binaryPath));
        }
        catch (Exception ex) when (ex is Win32Exception or FileNotFoundException or InvalidOperationException)
        {
            throw new DockerUnavailableException(DockerUnavailableException.NotInstalled, ex);
        }

        // Il daemon può spegnersi in qualunque momento, anche fra un comando e l'altro di una
        // pulizia: ogni chiamata lo verifica, non solo la prima.
        if (result.ExitCode != 0 && DockerCliErrors.IsDaemonUnavailable(result.StdErr))
        {
            throw new DockerUnavailableException(DockerUnavailableException.NotRunning);
        }

        return result;
    }

    /// <summary>
    /// Un'app aperta dal Finder riceve un PATH minimo (/usr/bin:/bin:…): la CLI di Docker
    /// Desktop cerca accanto a sé i propri helper (credential helper, plugin), quindi la sua
    /// cartella va in testa.
    /// </summary>
    private static Dictionary<string, string> Environment(string binary)
    {
        string directory = Path.GetDirectoryName(binary) ?? "/usr/local/bin";
        string inherited = System.Environment.GetEnvironmentVariable("PATH") ?? string.Empty;

        return new Dictionary<string, string>
        {
            ["PATH"] = $"{directory}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:{inherited}".TrimEnd(':'),
        };
    }
}

public static class DockerBinaryLocator
{
    /// <summary>Percorsi noti, in ordine: Docker Desktop per l'utente, installazione di sistema, Homebrew, bundle dell'app.</summary>
    public static string? Find(IFileSystem fileSystem, string homeDirectory)
    {
        string[] candidates =
        [
            fileSystem.Path.Combine(homeDirectory, ".docker", "bin", "docker"),
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ];

        return candidates.FirstOrDefault(fileSystem.File.Exists);
    }
}
