using System.Text.RegularExpressions;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Xcode;

public enum XcodeRunningState { Unknown, NotRunning, Running }

public interface IXcodeRunningProbe
{
    Task<XcodeRunningState> GetStateAsync(CancellationToken ct);
}

/// <summary>Reads process paths directly so an unavailable process listing cannot be mistaken for Xcode being closed.</summary>
public sealed partial class XcodeRunningProbe(IProcessRunner runner) : IXcodeRunningProbe
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(5);

    [GeneratedRegex(@"/(?:Xcode|Xcode-beta)\.app/Contents/MacOS/", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex XcodeBundlePath();

    public async Task<XcodeRunningState> GetStateAsync(CancellationToken ct)
    {
        try
        {
            ProcessResult result = await runner.RunAsync("ps", ["-axo", "comm="], Timeout, ct);
            if (result.TimedOut || result.ExitCode != 0 || !string.IsNullOrWhiteSpace(result.StdErr))
            {
                return XcodeRunningState.Unknown;
            }

            return result.StdOut.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Any(path => XcodeBundlePath().IsMatch(path))
                ? XcodeRunningState.Running
                : XcodeRunningState.NotRunning;
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            return XcodeRunningState.Unknown;
        }
    }
}
