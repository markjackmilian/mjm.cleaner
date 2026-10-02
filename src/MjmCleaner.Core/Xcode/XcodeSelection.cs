using System.Collections.ObjectModel;

namespace MjmCleaner.Core.Xcode;

public sealed class XcodeConfirmation
{
    internal XcodeConfirmation(XcodeSnapshot sourceSnapshot, IReadOnlyList<XcodeCandidate> selectedCandidates, IReadOnlyList<XcodeCandidate> retainedDependentDevices, long estimatedBytes, int unknownSizeCount)
    {
        SourceSnapshot = sourceSnapshot;
        SelectedCandidates = selectedCandidates;
        RetainedDependentDevices = retainedDependentDevices;
        EstimatedBytes = estimatedBytes;
        UnknownSizeCount = unknownSizeCount;
    }

    public IReadOnlyList<XcodeCandidate> SelectedCandidates { get; }
    public IReadOnlyList<XcodeCandidate> RetainedDependentDevices { get; }
    public long EstimatedBytes { get; }
    public int UnknownSizeCount { get; }
    internal XcodeSnapshot SourceSnapshot { get; }
}

public sealed class XcodeConfirmedPlan
{
    internal XcodeConfirmedPlan(XcodeSnapshot sourceSnapshot, IReadOnlyList<XcodeCandidate> candidates, XcodeFileInventory fileInventory)
    {
        SourceSnapshot = sourceSnapshot;
        Candidates = candidates;
        FileInventory = fileInventory;
    }

    public IReadOnlyList<XcodeCandidate> Candidates { get; }
    public XcodeFileInventory FileInventory { get; }
    public XcodeSnapshot SourceSnapshot { get; }
}

public static class XcodeSelection
{
    public static XcodeConfirmation Preview(XcodeSnapshot snapshot, IReadOnlySet<string> selectedKeys)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentNullException.ThrowIfNull(selectedKeys);

        snapshot = XcodeClassifier.Classify(snapshot, xcodeRunning: false);
        Dictionary<string, XcodeCandidate> candidatesByKey = new(StringComparer.Ordinal);
        foreach (XcodeCandidate candidate in snapshot.Candidates)
        {
            string normalized = XcodeClassifier.NormalizeSelectionKey(candidate.Key);
            if (!candidatesByKey.TryAdd(normalized, candidate))
            {
                throw new ArgumentException("Xcode inventory contains duplicate candidate keys.", nameof(snapshot));
            }
        }

        HashSet<string> selected = new(StringComparer.Ordinal);
        foreach (string? rawKey in selectedKeys)
        {
            if (rawKey is null)
            {
                throw new ArgumentException("Selection contains an empty key.", nameof(selectedKeys));
            }

            string key = XcodeClassifier.NormalizeSelectionKey(rawKey);
            if (!selected.Add(key))
            {
                continue;
            }

            if (!candidatesByKey.TryGetValue(key, out XcodeCandidate? candidate))
            {
                throw new ArgumentException($"Unknown Xcode candidate key: {rawKey}", nameof(selectedKeys));
            }

            if (!candidate.CanSelect)
            {
                throw new ArgumentException($"Xcode candidate is blocked: {candidate.Name}: {candidate.BlockReason}", nameof(selectedKeys));
            }
        }

        XcodeCandidate[] chosen = candidatesByKey.Where(pair => selected.Contains(pair.Key)).Select(pair => CopyCandidate(pair.Value)).ToArray();
        HashSet<string> chosenKeys = chosen.Select(candidate => XcodeClassifier.NormalizeSelectionKey(candidate.Key)).ToHashSet(StringComparer.Ordinal);
        Dictionary<string, XcodeCandidate> allByKey = candidatesByKey;
        XcodeCandidate[] retained = chosen.Where(candidate => candidate.Kind == XcodeResourceKind.Runtime)
            .SelectMany(runtime => runtime.DependentDeviceKeys)
            .Where(dependencyKey => !chosenKeys.Contains(XcodeClassifier.NormalizeSelectionKey(dependencyKey)))
            .Select(dependencyKey => allByKey.TryGetValue(XcodeClassifier.NormalizeSelectionKey(dependencyKey), out XcodeCandidate? device) && device.Kind == XcodeResourceKind.Device ? CopyCandidate(device) : null)
            .Where(device => device is not null)
            .Cast<XcodeCandidate>()
            .DistinctBy(candidate => XcodeClassifier.NormalizeSelectionKey(candidate.Key))
            .ToArray();

        int unknownCount = chosen.Count(candidate => candidate.SizeBytes is null);
        long knownBytes = chosen.Where(candidate => candidate.SizeBytes.HasValue).Sum(candidate => candidate.SizeBytes!.Value);
        XcodeSnapshot copiedSnapshot = CopySnapshot(snapshot);
        return new XcodeConfirmation(copiedSnapshot, Array.AsReadOnly(chosen), Array.AsReadOnly(retained), knownBytes, unknownCount);
    }

    public static XcodeConfirmedPlan Confirm(XcodeConfirmation preview, bool acknowledgeDependencies)
    {
        ArgumentNullException.ThrowIfNull(preview);
        if (preview.SelectedCandidates.Count == 0)
        {
            throw new InvalidOperationException("No Xcode resources were selected.");
        }

        if (preview.RetainedDependentDevices.Count > 0 && !acknowledgeDependencies)
        {
            throw new InvalidOperationException("Acknowledge the retained devices that depend on the selected runtime.");
        }

        XcodeCandidate[] copied = preview.SelectedCandidates.Select(CopyCandidate).ToArray();
        Dictionary<string, XcodeFileEntry> inventory = new(StringComparer.Ordinal);
        foreach (XcodeCandidate candidate in copied)
        {
            if (preview.SourceSnapshot.FileInventory.TryGetValue(candidate.Key, out XcodeFileEntry? entry))
            {
                inventory[candidate.Key] = entry;
            }
        }

        return new XcodeConfirmedPlan(preview.SourceSnapshot, Array.AsReadOnly(copied), new XcodeFileInventory(inventory));
    }

    private static XcodeSnapshot CopySnapshot(XcodeSnapshot source)
        => new(Array.AsReadOnly(source.Candidates.Select(CopyCandidate).ToArray()), Array.AsReadOnly(source.Warnings.ToArray()))
        {
            FileInventory = new XcodeFileInventory(source.FileInventory),
        };

    private static XcodeCandidate CopyCandidate(XcodeCandidate candidate)
        => candidate with { Dependencies = Array.AsReadOnly(candidate.DependentDeviceKeys.ToArray()) };
}
