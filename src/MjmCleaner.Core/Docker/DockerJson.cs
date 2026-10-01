using System.Text.Json;

namespace MjmCleaner.Core.Docker;

/// <summary>L'output della CLI non è nel formato atteso: nessuna classificazione è possibile.</summary>
public sealed class DockerOutputException(string message, Exception? inner = null) : Exception(message, inner);

/// <summary>Dimensioni che solo <c>docker system df -v</c> conosce: esclusiva per immagine, totale per volume.</summary>
public sealed record DockerDfVerbose(
    IReadOnlyDictionary<string, long> ImageUniqueSizes,
    IReadOnlyDictionary<string, long> VolumeSizes);

/// <summary>
/// Parsing puro dell'output JSON della CLI, mai delle tabelle: le colonne cambiano larghezza e
/// ordine fra le versioni, il JSON no. Tollerante verso campi assenti o <c>null</c> — misurato:
/// <c>Config.Labels</c> manca del tutto su alcune immagini (azurelinux) e <c>Labels</c> di un
/// volume senza etichette è <c>null</c>, non un oggetto vuoto.
/// </summary>
public static class DockerJson
{
    private static readonly IReadOnlyDictionary<string, string> NoLabels = new Dictionary<string, string>();

    public static IReadOnlyList<DockerContainer> ParseContainers(string inspectJson)
        => ParseArray(inspectJson, "container", element => new DockerContainer(
            Id: String(element, "Id") ?? string.Empty,
            Name: (String(element, "Name") ?? string.Empty).TrimStart('/'),
            ImageId: String(element, "Image") ?? string.Empty,
            State: String(Child(element, "State"), "Status") ?? string.Empty,
            ExitCode: Child(element, "State") is { } state && state.TryGetProperty("ExitCode", out JsonElement code)
                      && code.ValueKind == JsonValueKind.Number ? code.GetInt32() : 0,
            VolumeNames: [.. Items(element, "Mounts")
                .Where(mount => String(mount, "Type") == "volume")
                .Select(mount => String(mount, "Name"))
                .OfType<string>()],
            Labels: Labels(Child(element, "Config"))));

    public static IReadOnlyList<DockerImage> ParseImages(
        string inspectJson,
        IReadOnlyDictionary<string, long>? uniqueSizes = null)
        => ParseArray(inspectJson, "immagine", element =>
        {
            string id = String(element, "Id") ?? string.Empty;
            return new DockerImage(
                Id: id,
                RepoTags: Strings(element, "RepoTags"),
                RepoDigests: Strings(element, "RepoDigests"),
                SizeBytes: element.TryGetProperty("Size", out JsonElement size) && size.ValueKind == JsonValueKind.Number
                    ? size.GetInt64()
                    : 0,
                UniqueSizeBytes: uniqueSizes is not null && uniqueSizes.TryGetValue(id, out long unique) ? unique : null,
                Labels: Labels(Child(element, "Config")),
                Origin: Origin(Child(element, "Identity")));
        });

    public static IReadOnlyList<DockerVolume> ParseVolumes(
        string inspectJson,
        IReadOnlyDictionary<string, long>? sizes = null)
        => ParseArray(inspectJson, "volume", element =>
        {
            string name = String(element, "Name") ?? string.Empty;
            return new DockerVolume(
                name,
                Labels(element),
                sizes is not null && sizes.TryGetValue(name, out long bytes) ? bytes : null);
        });

    public static DockerDfVerbose ParseDfVerbose(string json)
    {
        using JsonDocument document = Parse(json, "docker system df -v");
        JsonElement root = document.RootElement;

        return new DockerDfVerbose(
            SizesBy(root, "Images", "ID", "UniqueSize"),
            SizesBy(root, "Volumes", "Name", "Size"));
    }

    /// <summary>Una riga JSON per tipo di risorsa: <c>docker system df --format '{{json .}}'</c>.</summary>
    public static DockerDfSummary ParseDfSummary(string jsonLines)
        => new([.. JsonLines(jsonLines, "docker system df").Select(line => new DockerDfEntry(
            String(line, "Type") ?? string.Empty,
            DockerSize.Parse(String(line, "Size")) ?? 0,
            DockerSize.Parse(String(line, "Reclaimable")) ?? 0))]);

    /// <summary>Un valore per riga: <c>docker ps -aq</c>.</summary>
    public static IReadOnlyList<string> ParseLines(string output)
        => [.. output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Distinct(StringComparer.Ordinal)];

    /// <summary>Un campo da ciascuna riga di un output <c>--format '{{json .}}'</c>.</summary>
    public static IReadOnlyList<string> ParseJsonLinesProperty(string jsonLines, string property)
        => [.. JsonLines(jsonLines, property)
            .Select(line => String(line, property))
            .OfType<string>()
            .Distinct(StringComparer.Ordinal)];

    // --- Utilità -----------------------------------------------------------------------------

    private static IReadOnlyList<T> ParseArray<T>(string json, string what, Func<JsonElement, T> map)
    {
        using JsonDocument document = Parse(json, what);

        if (document.RootElement.ValueKind != JsonValueKind.Array)
        {
            throw new DockerOutputException($"Risposta di Docker inattesa per {what}: atteso un elenco JSON.");
        }

        return [.. document.RootElement.EnumerateArray().Select(map)];
    }

    private static List<JsonElement> JsonLines(string jsonLines, string what)
    {
        List<JsonElement> lines = [];

        foreach (string line in jsonLines.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            using JsonDocument document = Parse(line, what);
            lines.Add(document.RootElement.Clone());
        }

        return lines;
    }

    private static JsonDocument Parse(string json, string what)
    {
        try
        {
            return JsonDocument.Parse(json);
        }
        catch (JsonException ex)
        {
            throw new DockerOutputException($"Risposta di Docker non leggibile per {what}.", ex);
        }
    }

    private static Dictionary<string, long> SizesBy(JsonElement root, string array, string key, string sizeProperty)
    {
        Dictionary<string, long> sizes = new(StringComparer.Ordinal);

        foreach (JsonElement item in Items(root, array))
        {
            if (String(item, key) is { } id && DockerSize.Parse(String(item, sizeProperty)) is { } bytes)
            {
                sizes[id] = bytes;
            }
        }

        return sizes;
    }

    private static ImageOrigin Origin(JsonElement? identity)
    {
        if (identity is null)
        {
            return ImageOrigin.Unknown;
        }

        // Pull vince su Build: un'immagine scaricata e poi ritaggata da una build resta
        // riscaricabile, che è ciò che la regola "costruita in locale" vuole sapere.
        if (Items(identity.Value, "Pull").Any())
        {
            return ImageOrigin.Pulled;
        }

        return Items(identity.Value, "Build").Any() ? ImageOrigin.Built : ImageOrigin.Unknown;
    }

    private static IReadOnlyDictionary<string, string> Labels(JsonElement? owner)
    {
        if (Child(owner, "Labels") is not { ValueKind: JsonValueKind.Object } labels)
        {
            return NoLabels;
        }

        return labels.EnumerateObject()
            .Where(p => p.Value.ValueKind == JsonValueKind.String)
            .ToDictionary(p => p.Name, p => p.Value.GetString()!, StringComparer.Ordinal);
    }

    private static JsonElement? Child(JsonElement? owner, string name)
        => owner is { ValueKind: JsonValueKind.Object } element
           && element.TryGetProperty(name, out JsonElement child)
           && child.ValueKind is not JsonValueKind.Null and not JsonValueKind.Undefined
            ? child
            : null;

    private static string? String(JsonElement? owner, string name)
        => Child(owner, name) is { ValueKind: JsonValueKind.String } value ? value.GetString() : null;

    private static IEnumerable<JsonElement> Items(JsonElement? owner, string name)
        => Child(owner, name) is { ValueKind: JsonValueKind.Array } array ? array.EnumerateArray() : [];

    private static IReadOnlyList<string> Strings(JsonElement owner, string name)
        => [.. Items(owner, name).Where(e => e.ValueKind == JsonValueKind.String).Select(e => e.GetString()!)];
}
