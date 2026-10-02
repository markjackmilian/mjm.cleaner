namespace MjmCleaner.Core.Xcode;

/// <summary>Applies current safety classifications without introducing any selected state.</summary>
public static class XcodeClassifier
{
    public static XcodeSnapshot Classify(XcodeSnapshot snapshot, bool xcodeRunning)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        HashSet<string> keys = new(StringComparer.Ordinal);
        foreach (XcodeCandidate candidate in snapshot.Candidates)
        {
            if (candidate is null || string.IsNullOrWhiteSpace(candidate.Key) || !keys.Add(NormalizeSelectionKey(candidate.Key)))
            {
                throw new ArgumentException("Xcode inventory contains a missing or duplicate candidate key.", nameof(snapshot));
            }
        }

        Dictionary<string, XcodeCandidate> byKey = snapshot.Candidates.ToDictionary(candidate => NormalizeSelectionKey(candidate.Key), StringComparer.Ordinal);
        XcodeCandidate[] classified = snapshot.Candidates.Select(candidate => ClassifyCandidate(candidate, byKey, xcodeRunning)).ToArray();
        return new XcodeSnapshot(Array.AsReadOnly(classified), Array.AsReadOnly(snapshot.Warnings.ToArray()))
        {
            FileInventory = new XcodeFileInventory(snapshot.FileInventory),
        };
    }

    private static XcodeCandidate ClassifyCandidate(XcodeCandidate candidate, IReadOnlyDictionary<string, XcodeCandidate> byKey, bool xcodeRunning)
    {
        string? block = candidate.BlockReason;
        if (candidate.Kind is XcodeResourceKind.DerivedData or XcodeResourceKind.DeviceSupport)
        {
            if (xcodeRunning)
            {
                block ??= "Chiudi Xcode e ripeti l'analisi prima di rimuovere file.";
            }
        }
        else if (candidate.Kind == XcodeResourceKind.Device)
        {
            bool identityVerified = IsMatchingUuid(candidate.Key, candidate.CliId);
            if (!identityVerified)
            {
                block ??= "Identità UUID del dispositivo non verificata.";
            }
            else if (IsRunning(candidate.State))
            {
                block = "Arresta il dispositivo in Xcode prima di rimuoverlo.";
            }
            else if (IsUnavailable(candidate.State))
            {
                // simctl's unavailable state is still individually addressable by a verified UUID.
                block = null;
            }
            else if (!IsShutdown(candidate.State))
            {
                block ??= "Stato del dispositivo non verificato; ripeti l'analisi.";
            }
        }
        else if (candidate.Kind == XcodeResourceKind.Runtime)
        {
            if (!IsRuntimeIdentityVerified(candidate))
            {
                block ??= "Identità del runtime non verificata.";
            }

            foreach (string dependencyKey in candidate.DependentDeviceKeys)
            {
                if (!byKey.TryGetValue(NormalizeSelectionKey(dependencyKey), out XcodeCandidate? dependency) || dependency.Kind != XcodeResourceKind.Device)
                {
                    block ??= "Dipendenze del runtime non verificate; ripeti l'analisi.";
                    continue;
                }

                if (IsRunning(dependency.State))
                {
                    block = "Un dispositivo che usa questo runtime è avviato; arrestalo in Xcode prima di rimuoverlo.";
                    break;
                }

                if (!IsShutdown(dependency.State) && !IsUnavailable(dependency.State))
                {
                    block ??= "Lo stato di un dispositivo che usa questo runtime non è verificato.";
                }
            }
        }

        return candidate with
        {
            BlockReason = block,
            Dependencies = Array.AsReadOnly(candidate.DependentDeviceKeys.ToArray()),
        };
    }

    internal static string NormalizeSelectionKey(string key)
    {
        if (Guid.TryParse(key, out Guid uuid))
        {
            return uuid.ToString("D");
        }

        const string runtimePrefix = "runtime:";
        if (key.StartsWith(runtimePrefix, StringComparison.OrdinalIgnoreCase) && Guid.TryParse(key[runtimePrefix.Length..], out uuid))
        {
            return runtimePrefix + uuid.ToString("D");
        }

        return key;
    }

    private static bool IsMatchingUuid(string key, string? cliId) => Guid.TryParse(key, out Guid keyUuid)
        && Guid.TryParse(cliId, out Guid cliUuid)
        && keyUuid == cliUuid;

    private static bool IsRuntimeIdentityVerified(XcodeCandidate candidate)
        => candidate.CliId is not null && Guid.TryParse(candidate.CliId, out _)
            && candidate.Key.StartsWith("runtime:", StringComparison.Ordinal)
            && Guid.TryParse(candidate.Key["runtime:".Length..], out Guid keyUuid)
            && Guid.TryParse(candidate.CliId, out Guid cliUuid)
            && keyUuid == cliUuid;

    private static bool IsRunning(string? state) => state is not null && (state.Equals("Booted", StringComparison.OrdinalIgnoreCase)
        || state.Equals("Booting", StringComparison.OrdinalIgnoreCase) || state.Equals("Starting", StringComparison.OrdinalIgnoreCase));
    private static bool IsShutdown(string? state) => state?.Equals("Shutdown", StringComparison.OrdinalIgnoreCase) == true;
    private static bool IsUnavailable(string? state) => state?.Equals("Unavailable", StringComparison.OrdinalIgnoreCase) == true;
}
