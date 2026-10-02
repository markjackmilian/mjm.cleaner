using System.Text.Json;

namespace MjmCleaner.Core.Xcode;

/// <summary>Parses the two independent, read-only simctl inventory formats.</summary>
public static class XcodeJson
{
    public static XcodeSnapshot ParseInventory(string? simctlJson, string? runtimeJson, bool runtimeDeleteSupported)
    {
        List<XcodeCandidate> candidates = [];
        List<XcodeInventoryWarning> warnings = [];
        List<LogicalRuntime> logicalRuntimes = [];
        List<XcodeCandidate> devices = [];
        bool deviceInventorySafe = true;
        bool logicalRuntimeInventorySafe = true;
        bool runtimeInventorySafe = true;

        JsonDocument? simctlDocument = null;
        try
        {
            simctlDocument = JsonDocument.Parse(simctlJson ?? string.Empty);
            if (simctlDocument.RootElement.ValueKind != JsonValueKind.Object)
            {
                throw new JsonException("L'inventario simulatori non è un oggetto JSON.");
            }
        }
        catch (JsonException ex)
        {
            simctlDocument?.Dispose();
            simctlDocument = null;
            deviceInventorySafe = false;
            logicalRuntimeInventorySafe = false;
            warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Device, $"Inventario simulatori non leggibile: {ex.Message}"));
            warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, "Inventario dei runtime logici non leggibile."));
        }

        if (simctlDocument is not null)
        {
            using (simctlDocument)
            {
                JsonElement root = simctlDocument.RootElement;
                if (!root.TryGetProperty("runtimes", out JsonElement runtimeArray) || runtimeArray.ValueKind != JsonValueKind.Array)
                {
                    logicalRuntimeInventorySafe = false;
                    warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, "Metadati dei runtime logici mancanti o non validi."));
                }
                else
                {
                    foreach (JsonElement runtime in runtimeArray.EnumerateArray())
                    {
                        string? identifier = String(runtime, "identifier");
                        string? build = String(runtime, "buildversion") ?? String(runtime, "buildVersion");
                        if (identifier is null || build is null)
                        {
                            logicalRuntimeInventorySafe = false;
                            continue;
                        }

                        logicalRuntimes.Add(new LogicalRuntime(identifier, build, String(runtime, "name") ?? identifier, String(runtime, "version"), String(runtime, "platform")));
                    }

                    if (!logicalRuntimeInventorySafe && warnings.All(w => w.ResourceGroup != XcodeResourceKind.Runtime))
                    {
                        warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, "Metadati dei runtime logici incompleti."));
                    }
                }

                if (!root.TryGetProperty("devices", out JsonElement deviceGroups) || deviceGroups.ValueKind != JsonValueKind.Object)
                {
                    deviceInventorySafe = false;
                    warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Device, "Elenco dispositivi mancante o non valido."));
                }
                else
                {
                    foreach (JsonProperty group in deviceGroups.EnumerateObject())
                    {
                        if (group.Value.ValueKind != JsonValueKind.Array)
                        {
                            deviceInventorySafe = false;
                            continue;
                        }

                        foreach (JsonElement device in group.Value.EnumerateArray())
                        {
                            string? uuid = String(device, "udid");
                            string? name = String(device, "name");
                            string? state = String(device, "state");
                            if (uuid is null || !IsUuid(uuid) || name is null)
                            {
                                deviceInventorySafe = false;
                                continue;
                            }

                            string? blockReason = DeviceBlockReason(state);
                            if (state is null || (!IsRunning(state) && !IsShutdown(state)))
                            {
                                deviceInventorySafe = false;
                            }

                            long? sizeBytes = OptionalInt64(device, "dataPathSize", out bool malformedSize);
                            if (malformedSize && warnings.All(w => w.ResourceGroup != XcodeResourceKind.Device || !w.Message.Contains("dimensione", StringComparison.OrdinalIgnoreCase)))
                            {
                                warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Device, "La dimensione di un dispositivo non è leggibile e resta sconosciuta."));
                            }

                            devices.Add(new XcodeCandidate(
                                Key: uuid,
                                Kind: XcodeResourceKind.Device,
                                Name: name,
                                CliId: uuid,
                                RuntimeIdentifier: group.Name,
                                State: state,
                                SizeBytes: sizeBytes,
                                BlockReason: blockReason));
                        }
                    }
                }
            }
        }

        if (!deviceInventorySafe && warnings.All(w => w.ResourceGroup != XcodeResourceKind.Device))
        {
            warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Device, "Inventario simulatori incompleto; la rimozione dei simulatori e dei runtime è disabilitata."));
        }

        if (!deviceInventorySafe)
        {
            devices = devices.Select(device => device with
            {
                BlockReason = device.BlockReason ?? "Inventario simulatori incompleto; ripeti l'analisi prima di rimuovere simulatori."
            }).ToList();
        }

        candidates.AddRange(devices);

        List<RuntimeImage> images = [];
        try
        {
            using JsonDocument document = JsonDocument.Parse(runtimeJson ?? string.Empty);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                throw new JsonException("Il JSON delle immagini runtime non è un oggetto.");
            }

            foreach (JsonProperty property in document.RootElement.EnumerateObject())
            {
                JsonElement image = property.Value;
                string? id = String(image, "identifier") ?? property.Name;
                string? runtimeIdentifier = String(image, "runtimeIdentifier");
                string? build = String(image, "build");
                string? version = String(image, "version");
                bool hasUuid = IsUuid(id);
                long? sizeBytes = OptionalInt64(image, "sizeBytes", out bool malformedSize);
                if (malformedSize && warnings.All(w => w.ResourceGroup != XcodeResourceKind.Runtime || !w.Message.Contains("dimensione", StringComparison.OrdinalIgnoreCase)))
                {
                    warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, "La dimensione di un'immagine runtime non è leggibile e resta sconosciuta."));
                }

                if (!hasUuid || runtimeIdentifier is null || build is null)
                {
                    runtimeInventorySafe = false;
                }

                images.Add(new RuntimeImage(id, hasUuid ? id : null, runtimeIdentifier, build, version, String(image, "state"), sizeBytes, Bool(image, "deletable")));
            }
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException)
        {
            runtimeInventorySafe = false;
            warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, $"Inventario immagini runtime non leggibile: {ex.Message}"));
        }

        if (!runtimeInventorySafe && warnings.All(w => w.ResourceGroup != XcodeResourceKind.Runtime))
        {
            warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, "Alcune immagini runtime non hanno identificatori verificabili."));
        }

        foreach (RuntimeImage image in images)
        {
            string? blockReason = null;
            IReadOnlyList<LogicalRuntime> exactMatches = image.RuntimeIdentifier is null || image.Build is null
                ? Array.Empty<LogicalRuntime>()
                : logicalRuntimes.Where(runtime => runtime.Identifier == image.RuntimeIdentifier && runtime.Build == image.Build).ToArray();

            if (image.CliId is null)
            {
                blockReason = "UUID di rimozione non disponibile.";
            }
            else if (!runtimeDeleteSupported)
            {
                blockReason = "Questa versione di Xcode non espone la rimozione dei runtime; gestiscili in Xcode Settings.";
            }
            else if (!runtimeInventorySafe)
            {
                blockReason = "Inventario immagini runtime incompleto; ripeti l'analisi.";
            }
            else if (!deviceInventorySafe)
            {
                blockReason = "Inventario simulatori incompleto; non è possibile verificare l'uso del runtime.";
            }
            else if (!logicalRuntimeInventorySafe)
            {
                blockReason = "Metadati dei runtime logici incompleti; ripeti l'analisi.";
            }
            else if (image.RuntimeIdentifier is null || image.Build is null || exactMatches.Count != 1)
            {
                blockReason = "Associazione tra runtime e build ambigua o non verificabile.";
            }
            else if (image.Deletable == false)
            {
                blockReason = "Xcode segnala che questa immagine runtime non è rimovibile.";
            }
            else if (images.Count(other => other.RuntimeIdentifier == image.RuntimeIdentifier && other.Version == image.Version) > 1
                || logicalRuntimes.Count(other => other.Identifier == image.RuntimeIdentifier && other.Version == image.Version) > 1)
            {
                blockReason = "Associazione runtime ambigua: più immagini hanno la stessa versione e le dipendenze dei simulatori non sono distinguibili con certezza.";
                if (warnings.All(w => w.ResourceGroup != XcodeResourceKind.Runtime))
                {
                    warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Runtime, "Associazione runtime/build ambigua: immagini con la stessa versione hanno build diverse."));
                }
            }

            XcodeCandidate[] dependentDevices = image.RuntimeIdentifier is null
                ? []
                : devices.Where(device => device.RuntimeIdentifier == image.RuntimeIdentifier).ToArray();
            if (blockReason is null && dependentDevices.Any(device => !IsShutdown(device.State)))
            {
                blockReason = dependentDevices.Any(device => IsRunning(device.State))
                    ? "Un dispositivo che usa questo runtime è avviato; arrestalo in Xcode prima di rimuoverlo."
                    : "Lo stato di un dispositivo che usa questo runtime non è verificato.";
            }

            string runtimeName = exactMatches.Count == 1
                ? exactMatches[0].Name
                : $"{image.RuntimeIdentifier ?? "Runtime sconosciuto"} {image.Version ?? image.Build ?? string.Empty}".Trim();
            candidates.Add(new XcodeCandidate(
                Key: $"runtime:{image.CliId ?? image.Id}",
                Kind: XcodeResourceKind.Runtime,
                Name: runtimeName,
                Path: null,
                CliId: image.CliId,
                RuntimeIdentifier: blockReason?.Contains("ambigua", StringComparison.OrdinalIgnoreCase) == true ? null : image.RuntimeIdentifier,
                Build: image.Build,
                State: image.State,
                SizeBytes: image.SizeBytes,
                BlockReason: blockReason,
                Dependencies: dependentDevices.Select(device => device.Key).ToArray()));
        }

        return new XcodeSnapshot(candidates, warnings);
    }

    private static string? String(JsonElement element, string property)
        => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(property, out JsonElement value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static long? OptionalInt64(JsonElement element, string property, out bool malformed)
    {
        malformed = false;
        if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(property, out JsonElement value))
        {
            return null;
        }

        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out long number))
        {
            return number;
        }

        malformed = true;
        return null;
    }

    private static bool? Bool(JsonElement element, string property)
        => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(property, out JsonElement value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? value.GetBoolean()
            : null;

    private static bool IsUuid(string value) => Guid.TryParseExact(value, "D", out _);

    private static bool IsRunning(string? state)
        => state is not null && (state.Equals("Booted", StringComparison.OrdinalIgnoreCase)
            || state.Equals("Booting", StringComparison.OrdinalIgnoreCase)
            || state.Equals("Starting", StringComparison.OrdinalIgnoreCase));

    private static bool IsShutdown(string? state) => state?.Equals("Shutdown", StringComparison.OrdinalIgnoreCase) == true;

    private static string? DeviceBlockReason(string? state)
    {
        if (IsShutdown(state))
        {
            return null;
        }

        if (IsRunning(state))
        {
            return "Arresta il dispositivo in Xcode prima di rimuoverlo.";
        }

        return $"Stato del dispositivo non verificato{(state is null ? string.Empty : $": {state}")}; ripeti l'analisi.";
    }

    private sealed record LogicalRuntime(string Identifier, string Build, string Name, string? Version, string? Platform);
    private sealed record RuntimeImage(string Id, string? CliId, string? RuntimeIdentifier, string? Build, string? Version, string? State, long? SizeBytes, bool? Deletable);
}
