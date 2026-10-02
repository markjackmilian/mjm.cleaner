using System.Globalization;
using System.IO.Abstractions;
using MjmCleaner.Core.Docker;
using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Xcode;

public interface IXcodeSizeProbe
{
    Task<long?> MeasureAsync(string path, CancellationToken ct);
    Task<long?> GetFreeBytesAsync(CancellationToken ct);
}

/// <summary>Read-only allocated-size and free-space estimates for the home volume.</summary>
public sealed class XcodeSizeProbe(
    IFileSystem fileSystem,
    IProcessRunner runner,
    ILinkInspector links,
    string homeDirectory) : IXcodeSizeProbe
{
    private static readonly TimeSpan MeasureTimeout = TimeSpan.FromSeconds(30);

    public async Task<long?> MeasureAsync(string path, CancellationToken ct)
    {
        try
        {
            if (!Path.IsPathFullyQualified(path) || links.IsSymbolicLink(path)
                || (!fileSystem.File.Exists(path) && !fileSystem.Directory.Exists(path)))
            {
                return null;
            }

            // BSD du does not follow symbolic links by default; -P makes that contract explicit.
            // A non-zero exit, timeout, or partial output is not a usable estimate.
            ProcessResult result = await runner.RunAsync("du", ["-k", "-s", "-P", path], MeasureTimeout, ct);
            if (result.ExitCode != 0 || result.TimedOut || !string.IsNullOrWhiteSpace(result.StdErr))
            {
                return null;
            }

            string[] rows = result.StdOut.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (rows.Length != 1)
            {
                return null;
            }

            string first = rows[0].Split(['\t', ' '], 2, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? string.Empty;
            return long.TryParse(first, NumberStyles.None, CultureInfo.InvariantCulture, out long kilobytes)
                && kilobytes >= 0 && kilobytes <= long.MaxValue / 1024
                    ? kilobytes * 1024
                    : null;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or ArgumentException or System.ComponentModel.Win32Exception)
        {
            return null;
        }
    }

    public Task<long?> GetFreeBytesAsync(CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        try
        {
            return Task.FromResult<long?>(fileSystem.DriveInfo.New(homeDirectory).AvailableFreeSpace);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or ArgumentException)
        {
            return Task.FromResult<long?>(null);
        }
    }
}
