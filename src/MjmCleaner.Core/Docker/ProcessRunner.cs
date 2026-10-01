using System.Diagnostics;

namespace MjmCleaner.Core.Docker;

public sealed record ProcessResult(int ExitCode, string StdOut, string StdErr, bool TimedOut);

public interface IProcessRunner
{
    Task<ProcessResult> RunAsync(
        string fileName,
        IReadOnlyList<string> args,
        TimeSpan timeout,
        CancellationToken ct,
        IReadOnlyDictionary<string, string>? environment = null);
}

/// <summary>
/// Avvia un processo con <see cref="ProcessStartInfo.ArgumentList"/>: ogni argomento arriva
/// intatto, senza una shell che lo reinterpreti — un nome di volume o un template
/// <c>{{json .}}</c> non possono diventare un comando diverso da quello scritto.
/// </summary>
public sealed class ProcessRunner : IProcessRunner
{
    public async Task<ProcessResult> RunAsync(
        string fileName,
        IReadOnlyList<string> args,
        TimeSpan timeout,
        CancellationToken ct,
        IReadOnlyDictionary<string, string>? environment = null)
    {
        ProcessStartInfo info = new(fileName)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        foreach (string arg in args)
        {
            info.ArgumentList.Add(arg);
        }

        if (environment is not null)
        {
            foreach ((string key, string value) in environment)
            {
                info.Environment[key] = value;
            }
        }

        using Process process = new() { StartInfo = info };
        process.Start();

        Task<string> stdout = process.StandardOutput.ReadToEndAsync(CancellationToken.None);
        Task<string> stderr = process.StandardError.ReadToEndAsync(CancellationToken.None);

        using CancellationTokenSource limit = CancellationTokenSource.CreateLinkedTokenSource(ct);
        limit.CancelAfter(timeout);

        try
        {
            await process.WaitForExitAsync(limit.Token);
        }
        catch (OperationCanceledException)
        {
            TryKill(process);

            if (ct.IsCancellationRequested)
            {
                throw;
            }

            return new ProcessResult(-1, string.Empty, string.Empty, TimedOut: true);
        }

        return new ProcessResult(process.ExitCode, await stdout, await stderr, TimedOut: false);
    }

    private static void TryKill(Process process)
    {
        try
        {
            process.Kill(entireProcessTree: true);
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            // Il processo può essere già terminato fra il timeout e il kill: non è un errore.
        }
    }
}
