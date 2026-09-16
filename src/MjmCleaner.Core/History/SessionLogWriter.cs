using System.IO.Abstractions;
using System.IO.Compression;
using System.Text.Json;
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

    private void Prune()
    {
        string[] files = [.. fileSystem.Directory
            .EnumerateFiles(paths.LogsDirectory, "session-*.jsonl.gz")
            .OrderDescending()];

        foreach (string stale in files.Skip(retention))
        {
            try
            {
                fileSystem.File.Delete(stale);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // La rotazione dei log non deve far fallire una pulizia riuscita.
            }
        }
    }
}
