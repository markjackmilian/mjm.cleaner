using System.ComponentModel;
using System.IO;
using System.Text.RegularExpressions;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Xcode;

/// <summary>Runs only read-only simctl inventory commands and UUID-targeted delete commands.</summary>
public sealed partial class XcodeCli(IProcessRunner runner, string? binaryPath) : IXcodeCli
{
    private static readonly TimeSpan InventoryTimeout = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan DeleteTimeout = TimeSpan.FromMinutes(5);

    public async Task<XcodeSnapshot> ReadInventoryAsync(CancellationToken ct)
    {
        string? simctlJson = null;
        string? runtimeJson = null;
        bool runtimeDeleteSupported = false;
        List<XcodeInventoryWarning> warnings = [];

        try
        {
            ProcessResult simctl = await RunAsync(["simctl", "list", "--json"], InventoryTimeout, ct);
            if (simctl.TimedOut || simctl.ExitCode != 0)
            {
                warnings.Add(XcodeInventoryWarning.CompletenessFailure(XcodeResourceKind.Device, $"Inventario simulatori non disponibile: {Describe(simctl)}"));
            }
            else
            {
                simctlJson = simctl.StdOut;
            }
        }
        catch (XcodeUnavailableException ex)
        {
            warnings.Add(XcodeInventoryWarning.CompletenessFailure(XcodeResourceKind.Device, ex.Message));
        }

        try
        {
            ProcessResult help = await RunAsync(["simctl", "runtime"], InventoryTimeout, ct);
            string helpText = $"{help.StdOut}\n{help.StdErr}";
            runtimeDeleteSupported = !help.TimedOut && Regex.IsMatch(helpText, @"(?m)^\s*delete\s+\(<identifier>", RegexOptions.CultureInvariant);
        }
        catch (XcodeUnavailableException ex)
        {
            warnings.Add(XcodeInventoryWarning.CompletenessFailure(XcodeResourceKind.Runtime, ex.Message));
        }

        try
        {
            ProcessResult runtime = await RunAsync(["simctl", "runtime", "list", "--json"], InventoryTimeout, ct);
            if (runtime.TimedOut || runtime.ExitCode != 0)
            {
                warnings.Add(XcodeInventoryWarning.CompletenessFailure(XcodeResourceKind.Runtime, $"Inventario immagini runtime non disponibile: {Describe(runtime)}"));
            }
            else
            {
                runtimeJson = runtime.StdOut;
            }

            if (!runtimeDeleteSupported)
            {
                warnings.Add(XcodeInventoryWarning.Advisory(XcodeResourceKind.Runtime, "Questa versione di Xcode non supporta la rimozione dei runtime dalla CLI; gestiscili in Xcode Settings."));
            }
        }
        catch (XcodeUnavailableException ex)
        {
            warnings.Add(XcodeInventoryWarning.CompletenessFailure(XcodeResourceKind.Runtime, ex.Message));
        }

        XcodeSnapshot parsed = XcodeJson.ParseInventory(simctlJson, runtimeJson, runtimeDeleteSupported);
        return new XcodeSnapshot(parsed.Candidates, warnings.Concat(parsed.Warnings).ToArray());
    }

    public Task<ProcessResult> DeleteDeviceAsync(string uuid, CancellationToken ct)
    {
        ValidateUuid(uuid);
        return RunAsync(["simctl", "delete", uuid], DeleteTimeout, ct);
    }

    public Task<ProcessResult> DeleteRuntimeAsync(string uuid, CancellationToken ct)
    {
        ValidateUuid(uuid);
        return RunAsync(["simctl", "runtime", "delete", uuid], DeleteTimeout, ct);
    }

    private async Task<ProcessResult> RunAsync(IReadOnlyList<string> args, TimeSpan timeout, CancellationToken ct)
    {
        if (binaryPath is null)
        {
            throw new XcodeUnavailableException("Xcode command line tools non trovati.");
        }

        try
        {
            return await runner.RunAsync(binaryPath, args, timeout, ct, Environment(binaryPath));
        }
        catch (Exception ex) when (ex is Win32Exception or FileNotFoundException or InvalidOperationException)
        {
            throw new XcodeUnavailableException("Xcode command line tools non trovati.", ex);
        }
    }

    private static Dictionary<string, string> Environment(string binary)
    {
        string directory = Path.GetDirectoryName(binary) ?? "/usr/bin";
        string inherited = System.Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        return new Dictionary<string, string>
        {
            ["PATH"] = $"{directory}:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:{inherited}".TrimEnd(':'),
        };
    }

    private static void ValidateUuid(string uuid)
    {
        if (!Guid.TryParseExact(uuid, "D", out _))
        {
            throw new ArgumentException("È richiesto un UUID esplicito; gli alias simctl non sono consentiti.", nameof(uuid));
        }
    }

    private static string Describe(ProcessResult result)
    {
        if (result.TimedOut)
        {
            return "timeout dopo 30 secondi";
        }

        return result.StdErr.Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()
            ?? $"codice di uscita {result.ExitCode}";
    }
}

public sealed class XcodeUnavailableException(string message, Exception? inner = null) : Exception(message, inner);
