using System.Globalization;
using System.IO.Abstractions;

namespace MjmCleaner.Core.Docker;

/// <param name="AllocatedBytes">Spazio realmente occupato sul disco (blocchi allocati, come <c>du</c>).</param>
/// <param name="ApparentBytes">Dimensione apparente: per un file sparse è solo il limite massimo del disco virtuale.</param>
public sealed record DockerDiskUsage(string Path, long? AllocatedBytes, long? ApparentBytes)
{
    public bool Exists => ApparentBytes is not null;
}

/// <summary>
/// Misura il disco virtuale di Docker Desktop. <c>Docker.raw</c> è un file sparse: la sua
/// dimensione apparente (misurata: 994 GB) è il limite configurato, non lo spazio occupato
/// (8,3 GB nello stesso momento). Solo i blocchi allocati dicono quanto disco si è recuperato.
/// Il file si legge e basta: la deny-list continua a proteggere l'intera cartella di Docker.
/// </summary>
public sealed class DiskUsageProbe(IProcessRunner runner, IFileSystem fileSystem, string diskImagePath)
{
    private static readonly TimeSpan DuTimeout = TimeSpan.FromSeconds(20);

    public static string DefaultPath(string homeDirectory)
        => $"{homeDirectory.TrimEnd('/')}/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw";

    public async Task<DockerDiskUsage> MeasureAsync(CancellationToken ct)
    {
        long? apparent;
        try
        {
            // Altre piattaforme, Docker non Desktop (Colima, OrbStack) o un disco spostato altrove:
            // il file può non esistere, e allora non c'è nulla da misurare.
            if (!fileSystem.File.Exists(diskImagePath))
            {
                return new DockerDiskUsage(diskImagePath, null, null);
            }

            apparent = fileSystem.FileInfo.New(diskImagePath).Length;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return new DockerDiskUsage(diskImagePath, null, null);
        }

        long? allocated = null;
        try
        {
            ProcessResult du = await runner.RunAsync("du", ["-k", diskImagePath], DuTimeout, ct);
            if (du.ExitCode == 0 && !du.TimedOut)
            {
                allocated = ParseDuKilobytes(du.StdOut);
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // Una misura non disponibile non deve impedire né l'analisi né la pulizia.
        }

        return new DockerDiskUsage(diskImagePath, allocated, apparent);
    }

    /// <summary>Prima colonna dell'output di <c>du -k</c>: blocchi da 1 KiB.</summary>
    public static long? ParseDuKilobytes(string output)
    {
        string first = output.Split(['\t', ' ', '\n'], 2, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? string.Empty;
        return long.TryParse(first, NumberStyles.None, CultureInfo.InvariantCulture, out long kb) ? kb * 1024 : null;
    }
}
