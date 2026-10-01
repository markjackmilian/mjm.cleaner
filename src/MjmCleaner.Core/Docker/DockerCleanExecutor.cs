using System.Diagnostics;
using System.Text.RegularExpressions;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Docker;

/// <summary>Identificativi stabili delle categorie Docker nello storico.</summary>
public static class DockerCategories
{
    public const string Images = "docker-images";
    public const string Volumes = "docker-volumes";
    public const string BuildCache = "docker-build-cache";

    public static string For(DockerResourceKind kind) => kind switch
    {
        DockerResourceKind.Image => Images,
        DockerResourceKind.Volume => Volumes,
        _ => BuildCache,
    };
}

/// <param name="After">Null quando la misura finale non è stata possibile (daemon spento a metà).</param>
public sealed record DockerCleanResult(
    CleanReport Report,
    DockerDfSummary Before,
    DockerDfSummary? After,
    bool DaemonLost);

/// <summary>
/// Esegue le sole cancellazioni confermate. Ogni garanzia di sicurezza è verificata qui, sul
/// singolo elemento, anche se l'interfaccia l'ha già applicata: la selezione arriva dall'interfaccia
/// e non va fidata, come in <see cref="CleanEngine"/>.
/// <list type="bullet">
/// <item>immagini solo per ID completo (<c>docker rmi sha256:…</c>), mai per tag;</item>
/// <item>mai <c>-f</c>/<c>--force</c>, mai <c>docker system prune</c>;</item>
/// <item>le voci KEEP non arrivano mai a un comando.</item>
/// </list>
/// Sequenziale: il daemon serializza comunque le cancellazioni, e un ordine prevedibile rende il
/// resoconto leggibile.
/// </summary>
public sealed partial class DockerCleanExecutor(IDockerCli cli, TimeProvider clock)
{
    private static readonly TimeSpan DeleteTimeout = TimeSpan.FromMinutes(10);

    [GeneratedRegex("^sha256:[0-9a-f]{64}$")]
    private static partial Regex FullImageId();

    // Stessa forma accettata da Docker per i nomi dei volumi: non può iniziare con "-", quindi
    // non può essere scambiato per un'opzione del comando.
    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9_.-]*$")]
    private static partial Regex VolumeName();

    public Task<DockerCleanResult> ExecuteAsync(
        IReadOnlyList<DockerCandidate> selected,
        IProgress<CleanProgress>? progress,
        CancellationToken ct)
        => Task.Run(() => RunAsync(selected, progress, ct), CancellationToken.None);

    private async Task<DockerCleanResult> RunAsync(
        IReadOnlyList<DockerCandidate> selected,
        IProgress<CleanProgress>? progress,
        CancellationToken ct)
    {
        DateTimeOffset startedAt = clock.GetUtcNow();
        long stamp = Stopwatch.GetTimestamp();

        // Senza la misura iniziale non si può dire quanto si è recuperato: se il daemon non
        // risponde nemmeno a questa, non si è cancellato nulla e l'errore risale all'interfaccia.
        DockerDfSummary before = await DockerInventoryCollector.ReadDfAsync(cli, ct);

        List<string> deleted = [];
        List<ScanError> errors = [];
        Dictionary<string, int> deletedByCategory = new(StringComparer.Ordinal);
        HashSet<DockerCandidate> handled = new(ReferenceEqualityComparer.Instance);
        List<DockerCandidate> retry = [];
        bool daemonLost = false;

        // Un passo per elemento. Restituisce false quando la pulizia va interrotta (daemon
        // sparito o annullamento): l'elemento non viene allora contato come gestito.
        async Task<bool> Step(DockerCandidate candidate, bool allowRetry)
        {
            if (daemonLost || ct.IsCancellationRequested)
            {
                return false;
            }

            if (Refusal(candidate) is { } refusal)
            {
                errors.Add(new ScanError(candidate.DisplayName, ScanErrorKind.Other, refusal));
            }
            else
            {
                ProcessResult result;
                try
                {
                    result = await cli.RunAsync(Command(candidate), CancellationToken.None, DeleteTimeout);
                }
                catch (DockerUnavailableException ex)
                {
                    daemonLost = true;
                    handled.Add(candidate);
                    errors.Add(new ScanError(candidate.DisplayName, ScanErrorKind.Other, ex.Message));
                    return false;
                }

                if (result.ExitCode == 0 && !result.TimedOut)
                {
                    deleted.Add(LogEntry(candidate));
                    string category = DockerCategories.For(candidate.Kind);
                    deletedByCategory[category] = deletedByCategory.GetValueOrDefault(category) + 1;
                }
                else if (allowRetry && HasDependentChildren(result))
                {
                    // Una base può precedere la propria derivata nell'elenco: si riprova una
                    // volta, dopo che le altre immagini sono state rimosse.
                    retry.Add(candidate);
                    return true;
                }
                else
                {
                    errors.Add(new ScanError(candidate.DisplayName, Classify(result), DockerCliErrors.Describe(result)));
                }
            }

            handled.Add(candidate);
            progress?.Report(new CleanProgress(candidate.DisplayName, handled.Count, selected.Count, 0));
            return true;
        }

        async Task<bool> Phase(IEnumerable<DockerCandidate> candidates, bool allowRetry)
        {
            foreach (DockerCandidate candidate in candidates)
            {
                if (!await Step(candidate, allowRetry))
                {
                    return false;
                }
            }

            return true;
        }

        // Fasi: immagini, ritentativi delle immagini con figlie, poi volumi e cache di build.
        _ = await Phase(selected.Where(c => c.Kind == DockerResourceKind.Image), allowRetry: true)
            && await Phase([.. retry], allowRetry: false)
            && await Phase(selected.Where(c => c.Kind != DockerResourceKind.Image).OrderBy(c => c.Kind), allowRetry: false);

        if (daemonLost)
        {
            // L'elemento in corso ha già il suo errore; quelli rimasti non sono stati tentati, e il
            // resoconto deve dirlo invece di lasciarli sparire.
            foreach (DockerCandidate skipped in selected.Where(c => !handled.Contains(c)))
            {
                errors.Add(new ScanError(skipped.DisplayName, ScanErrorKind.Other, "non eseguito: " + DockerUnavailableException.NotRunning));
            }
        }

        DockerDfSummary? after = daemonLost ? null : await TryReadDfAsync();

        CategoryCleanResult[] categories =
        [
            .. deletedByCategory.Select(entry => new CategoryCleanResult(
                entry.Key,
                after is null ? 0 : Math.Max(0, Size(before, entry.Key) - Size(after, entry.Key)),
                entry.Value)),
        ];

        CleanReport report = new(
            startedAt,
            Stopwatch.GetElapsedTime(stamp),
            categories.Sum(c => c.BytesFreed),
            deleted.Count,
            errors.Count,
            categories,
            errors,
            deleted);

        return new DockerCleanResult(report, before, after, daemonLost);
    }

    private async Task<DockerDfSummary?> TryReadDfAsync()
    {
        try
        {
            return await DockerInventoryCollector.ReadDfAsync(cli, CancellationToken.None);
        }
        catch (Exception ex) when (ex is DockerUnavailableException or DockerCommandException or DockerOutputException)
        {
            return null;
        }
    }

    private static string? Refusal(DockerCandidate candidate)
    {
        if (candidate.Verdict == DockerVerdict.Keep)
        {
            return "esito KEEP: non si cancella";
        }

        return candidate.Kind switch
        {
            DockerResourceKind.Image when !FullImageId().IsMatch(candidate.Id)
                => "identificativo non valido: le immagini si cancellano solo per ID completo",
            DockerResourceKind.Volume when !VolumeName().IsMatch(candidate.Id)
                => "nome di volume non valido",
            _ => null,
        };
    }

    private static IReadOnlyList<string> Command(DockerCandidate candidate) => candidate.Kind switch
    {
        DockerResourceKind.Image => ["rmi", candidate.Id],
        DockerResourceKind.Volume => ["volume", "rm", candidate.Id],
        // Qui -f salta solo la domanda interattiva di conferma: senza --all restano le voci
        // della cache ancora referenziate.
        _ => ["builder", "prune", "-f"],
    };

    private static string LogEntry(DockerCandidate candidate) => candidate.Kind switch
    {
        DockerResourceKind.Image => $"docker:image:{candidate.Id} ({candidate.DisplayName})",
        DockerResourceKind.Volume => $"docker:volume:{candidate.Id}",
        _ => "docker:build-cache",
    };

    private static bool HasDependentChildren(ProcessResult result)
        => result.StdErr.Contains("dependent child images", StringComparison.OrdinalIgnoreCase);

    private static ScanErrorKind Classify(ProcessResult result)
    {
        string text = result.StdErr;
        if (text.Contains("No such", StringComparison.OrdinalIgnoreCase))
        {
            return ScanErrorKind.NotFound;
        }

        return text.Contains("in use", StringComparison.OrdinalIgnoreCase) || text.Contains("being used", StringComparison.OrdinalIgnoreCase)
            ? ScanErrorKind.InUse
            : ScanErrorKind.Other;
    }

    private static long Size(DockerDfSummary df, string category) => category switch
    {
        DockerCategories.Images => df.Images,
        DockerCategories.Volumes => df.Volumes,
        _ => df.BuildCache,
    };
}
