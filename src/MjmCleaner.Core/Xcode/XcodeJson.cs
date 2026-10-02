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
        bool runtimeInventorySafe = true;

        try
        {
            using JsonDocument document = JsonDocument.Parse(simctlJson ?? string.Empty);
            JsonElement root = document.RootElement;
            JsonElement runtimeArray = root.GetProperty("runtimes");
            if (runtimeArray.ValueKind != JsonValueKind.Array)
            {
                throw new JsonException("The runtimes field is not an array.");
            }

            foreach (JsonElement runtime in runtimeArray.EnumerateArray())
            {
                string? identifier = String(runtime, "identifier");
                string? build = String(runtime, "buildversion") ?? String(runtime, "buildVersion");
                if (identifier is null || build is null)
                {
                    deviceInventorySafe = false;
                    continue;
                }

                logicalRuntimes.Add(new LogicalRuntime(identifier, build, String(runtime, "name") ?? identifier, String(runtime, "version"), String(runtime, "platform")));
            }

            JsonElement deviceGroups = root.GetProperty("devices");
            if (deviceGroups.ValueKind != JsonValueKind.Object)
            {
                throw new JsonException("The devices field is not an object.");
            }

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
                    if (uuid is null || !IsUuid(uuid) || name is null || state is null)
                    {
                        deviceInventorySafe = false;
                        continue;
                    }

                    string? blockReason = IsRunning(state) ? "Arresta il dispositivo in Xcode prima di rimuoverlo." : null;
                    devices.Add(new XcodeCandidate(
                        Key: uuid,
                        Kind: XcodeResourceKind.Device,
                        Name: name,
                        CliId: uuid,
                        RuntimeIdentifier: group.Name,
                        State: state,
                        SizeBytes: Int64(device, "dataPathSize"),
                        BlockReason: blockReason));
                }
            }
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or KeyNotFoundException)
        {
            deviceInventorySafe = false;
            warnings.Add(new XcodeInventoryWarning(XcodeResourceKind.Device, $"Inventario simulatori non leggibile: {ex.Message}"));
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
                if (!hasUuid || runtimeIdentifier is null || build is null)
                {
                    runtimeInventorySafe = false;
                }

                images.Add(new RuntimeImage(id, hasUuid ? id : null, runtimeIdentifier, build, version, String(image, "state"), Int64(image, "sizeBytes"), Bool(image, "deletable")));
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
            if (blockReason is null && dependentDevices.Any(device => IsRunning(device.State)))
            {
                blockReason = "Un dispositivo che usa questo runtime è avviato; arrestalo in Xcode prima di rimuoverlo.";
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

    private static long? Int64(JsonElement element, string property)
        => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(property, out JsonElement value) && value.TryGetInt64(out long number)
            ? number
            : null;

    private static bool? Bool(JsonElement element, string property)
        => element.ValueKind == JsonValueKind.Object && element.TryGetProperty(property, out JsonElement value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? value.GetBoolean()
            : null;

    private static bool IsUuid(string value) => Guid.TryParseExact(value, "D", out _);

    private static bool IsRunning(string? state)
        => state is not null && (state.Equals("Booted", StringComparison.OrdinalIgnoreCase)
            || state.Equals("Booting", StringComparison.OrdinalIgnoreCase)
            || state.Equals("Starting", StringComparison.OrdinalIgnoreCase));

    private sealed record LogicalRuntime(string Identifier, string Build, string Name, string? Version, string? Platform);
    private sealed record RuntimeImage(string Id, string? CliId, string? RuntimeIdentifier, string? Build, string? Version, string? State, long? SizeBytes, bool? Deletable);
}
