using System.IO.Abstractions;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Xcode;

/// <summary>Scans only the approved user Xcode cache and Device Support folders.</summary>
public sealed class XcodeFileScanner(
    IFileSystem fileSystem,
    RuleScanner ruleScanner,
    IPathGuard guard,
    ILinkInspector links,
    IXcodeSizeProbe sizeProbe,
    string homeDirectory) : IXcodeFileScanner
{
    public async Task<XcodeSnapshot> ScanAsync(CancellationToken ct)
    {
        List<XcodeCandidate> candidates = [];
        List<XcodeInventoryWarning> warnings = [];
        Dictionary<string, XcodeFileEntry> inventory = new(StringComparer.Ordinal);
        string xcodeRoot = fileSystem.Path.Combine(homeDirectory, "Library", "Developer", "Xcode");

        await ScanRootAsync(fileSystem.Path.Combine(xcodeRoot, "DerivedData"), XcodeResourceKind.DerivedData, null);
        foreach (string platform in new[] { "iOS", "watchOS", "tvOS", "visionOS" })
        {
            await ScanRootAsync(fileSystem.Path.Combine(xcodeRoot, $"{platform} DeviceSupport"), XcodeResourceKind.DeviceSupport, platform);
        }

        return new XcodeSnapshot(candidates, warnings) { FileInventory = new XcodeFileInventory(inventory) };

        async Task ScanRootAsync(string root, XcodeResourceKind kind, string? platform)
        {
            ct.ThrowIfCancellationRequested();
            if (!fileSystem.Directory.Exists(root))
            {
                return;
            }

            if (links.IsSymbolicLink(root))
            {
                warnings.Add(new XcodeInventoryWarning(kind, $"La root Xcode è un collegamento simbolico e non viene scansionata: {root}"));
                return;
            }

            CleanupRule rule = new(root, ScanMode.MatchingDirs, ["*"], [], MaxDepth: 1);
            RuleScanOutcome outcome = ruleScanner.Scan(rule, ct);
            if (outcome.Errors.Count > 0 || outcome.Exclusions.Count > 0)
            {
                warnings.Add(new XcodeInventoryWarning(kind, "Inventario incompleto: alcune cartelle non sono leggibili o non superano i controlli di percorso."));
            }

            foreach (ScanItem item in outcome.Items)
            {
                ct.ThrowIfCancellationRequested();
                // The direct-child rule only yields directories, but recheck the link boundary
                // immediately before metadata and size reads.
                GuardVerdict verdict = guard.Validate(item.Path, root);
                if (!verdict.IsAllowed || links.IsSymbolicLink(item.Path) || !fileSystem.Directory.Exists(item.Path))
                {
                    warnings.Add(new XcodeInventoryWarning(kind, $"Una cartella Xcode è stata saltata perché è cambiata o non è sicura: {fileSystem.Path.GetFileName(item.Path)}"));
                    continue;
                }

                string canonical = verdict.CanonicalPathValidated;
                string key = kind == XcodeResourceKind.DerivedData
                    ? $"derived-data:{canonical}"
                    : $"device-support:{platform}:{canonical}";
                if (inventory.ContainsKey(key))
                {
                    continue;
                }

                DateTime creation;
                DateTime modified;
                try
                {
                    creation = fileSystem.DirectoryInfo.New(canonical).CreationTimeUtc;
                    modified = fileSystem.DirectoryInfo.New(canonical).LastWriteTimeUtc;
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    warnings.Add(new XcodeInventoryWarning(kind, $"Una cartella Xcode è stata saltata perché i metadati non sono leggibili: {fileSystem.Path.GetFileName(item.Path)}"));
                    continue;
                }

                long? allocated = await sizeProbe.MeasureAsync(canonical, ct);
                XcodeFileIdentity identity = new(canonical, true, creation, modified, item.SizeBytes);
                ScanItem guardedItem = item with { Path = canonical, DeclaredRoot = root };
                inventory.Add(key, new XcodeFileEntry(guardedItem, identity));
                string name = fileSystem.Path.GetFileName(canonical);
                candidates.Add(new XcodeCandidate(
                    Key: key,
                    Kind: kind,
                    Name: platform is null ? name : $"{platform}: {name}",
                    Path: canonical,
                    SizeBytes: allocated));
            }
        }
    }

    /// <summary>Measures reported runtime backing images, never their mounted volume paths.</summary>
    public async Task<XcodeSnapshot> MeasureRuntimeBackingImagesAsync(XcodeSnapshot snapshot, CancellationToken ct)
    {
        List<XcodeInventoryWarning> warnings = [.. snapshot.Warnings];
        List<XcodeCandidate> candidates = [.. snapshot.Candidates];
        HashSet<string> seenPaths = new(StringComparer.Ordinal);
        string? firstPath = null;

        foreach (int index in Enumerable.Range(0, candidates.Count).Where(i => candidates[i].Kind == XcodeResourceKind.Runtime))
        {
            ct.ThrowIfCancellationRequested();
            XcodeCandidate candidate = candidates[index];
            if (string.IsNullOrWhiteSpace(candidate.Path) || !fileSystem.Path.IsPathRooted(candidate.Path))
            {
                candidates[index] = candidate with { SizeBytes = null };
                warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, $"Dimensione sconosciuta per {candidate.Name}: percorso dell'immagine runtime non disponibile."));
                continue;
            }

            string? root = fileSystem.Path.GetDirectoryName(candidate.Path);
            if (root is null)
            {
                candidates[index] = candidate with { SizeBytes = null };
                warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, $"Dimensione sconosciuta per {candidate.Name}: percorso dell'immagine runtime non valido."));
                continue;
            }

            GuardVerdict rootVerdict = guard.ValidateRoot(root);
            GuardVerdict verdict = rootVerdict.IsAllowed ? guard.Validate(candidate.Path, root) : rootVerdict;
            if (!verdict.IsAllowed || links.IsSymbolicLink(candidate.Path))
            {
                candidates[index] = candidate with { SizeBytes = null };
                warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, $"Dimensione sconosciuta per {candidate.Name}: il percorso dell'immagine non supera i controlli di sicurezza."));
                continue;
            }

            string canonical = verdict.CanonicalPathValidated;
            if (!seenPaths.Add(canonical))
            {
                candidates[index] = candidate with { Path = canonical, SizeBytes = null };
                warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, $"Immagine runtime condivisa con {firstPath}: la dimensione viene conteggiata una sola volta."));
                continue;
            }

            firstPath = canonical;
            candidates[index] = candidate with { Path = canonical, SizeBytes = await sizeProbe.MeasureAsync(canonical, ct) };
        }

        return new XcodeSnapshot(candidates, warnings) { FileInventory = snapshot.FileInventory };
    }
}

public interface IXcodeFileScanner
{
    Task<XcodeSnapshot> ScanAsync(CancellationToken ct);
}
