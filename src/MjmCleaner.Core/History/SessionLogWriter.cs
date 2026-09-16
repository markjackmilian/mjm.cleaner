using System.IO.Abstractions;
using System.IO.Compression;
using System.Text.Json;
using System.Text.RegularExpressions;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.Core.History;

public interface ISessionLogWriter
{
    Task WriteAsync(long sessionId, CleanReport report, CancellationToken ct);
}

/// <summary>
/// Elenco completo dei percorsi eliminati, una riga JSON per elemento, compresso.
/// Non va in SQLite: una pulizia delle cache tocca centinaia di migliaia di file e
/// il database crescerebbe più in fretta dello spazio liberato.
/// </summary>
public sealed class SessionLogWriter(IFileSystem fileSystem, AppPaths paths, int retention = 20)
    : ISessionLogWriter
{
    public async Task WriteAsync(long sessionId, CleanReport report, CancellationToken ct)
    {
        fileSystem.Directory.CreateDirectory(paths.LogsDirectory);

        string file = fileSystem.Path.Combine(paths.LogsDirectory, FileName(sessionId));

        await using (Stream raw = fileSystem.File.Create(file))
        await using (GZipStream zipped = new(raw, CompressionLevel.Optimal))
        await using (StreamWriter writer = new(zipped))
        {
            foreach (string path in report.DeletedPaths)
            {
                ct.ThrowIfCancellationRequested();
                await writer.WriteLineAsync(JsonSerializer.Serialize(new { path }));
            }
        }

        Prune();
    }

    private static string FileName(long sessionId) => $"session-{sessionId:D6}.jsonl.gz";

    // Ancorato: solo "session-<cifre>.jsonl.gz" per intero, non un prefisso/suffisso.
    private static readonly Regex SessionFileNamePattern = new(@"^session-(\d+)\.jsonl\.gz$", RegexOptions.Compiled);

    private void Prune()
    {
        // L'ordinamento deve avvenire sul valore NUMERICO del nome file, non sulla stringa:
        // oltre le sei cifre (session-1000000...) l'ordinamento lessicografico mette "1..."
        // prima di "9...", e la rotazione cancellerebbe la sessione più recente invece della
        // più vecchia. I nomi senza un numero valido non sono file nostri: si escludono
        // dall'ordinamento e non si cancellano mai.
        string[] stale = [.. fileSystem.Directory
            .EnumerateFiles(paths.LogsDirectory, "session-*.jsonl.gz")
            .Select(path => (Path: path, SessionId: ExtractSessionId(path)))
            .Where(entry => entry.SessionId.HasValue)
            .OrderByDescending(entry => entry.SessionId!.Value)
            .Skip(retention)
            .Select(entry => entry.Path)];

        foreach (string path in stale)
        {
            try
            {
                fileSystem.File.Delete(path);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // La rotazione dei log non deve far fallire una pulizia riuscita.
            }
        }
    }

    private long? ExtractSessionId(string path)
    {
        Match match = SessionFileNamePattern.Match(fileSystem.Path.GetFileName(path));
        return match.Success && long.TryParse(match.Groups[1].Value, out long id) ? id : null;
    }
}
