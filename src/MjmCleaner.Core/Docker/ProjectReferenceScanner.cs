using System.IO.Abstractions;
using System.Text.RegularExpressions;

namespace MjmCleaner.Core.Docker;

/// <summary>
/// Cerca nei file dei progetti le immagini che vi sono citate: un'immagine che un compose, un
/// Dockerfile o un AppHost useranno al prossimo avvio non va proposta per la cancellazione solo
/// perché oggi nessun container la usa. Regex per riga o per istruzione, non un parser YAML/C#:
/// deve restare veloce su un'intera cartella di progetti, e un riferimento mancato costa al
/// massimo una voce PROPOSE che l'utente vede e può lasciare deselezionata.
/// </summary>
public sealed partial class ProjectReferenceScanner(IFileSystem fileSystem)
{
    private const long MaxFileBytes = 1024 * 1024;
    private const int MaxDepth = 12;

    private static readonly HashSet<string> ExcludedDirectories = new(StringComparer.OrdinalIgnoreCase)
    {
        "node_modules", "bin", "obj", ".git", ".hg", ".svn", ".vs", ".idea", "packages",
        ".venv", "venv", "__pycache__", "dist", "target", ".gradle", "Pods", "DerivedData",
    };

    /// <summary>Metodi di hosting di .NET Aspire → repository dell'immagine che avviano.</summary>
    private static readonly Dictionary<string, string> AspireResources = new(StringComparer.Ordinal)
    {
        ["SqlServer"] = "mcr.microsoft.com/mssql/server",
        ["Keycloak"] = "quay.io/keycloak/keycloak",
        ["AzureStorage"] = "mcr.microsoft.com/azure-storage/azurite",
        ["AzureCosmosDB"] = "mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator",
        ["AzureServiceBus"] = "mcr.microsoft.com/azure-messaging/servicebus-emulator",
        ["AzureEventHubs"] = "mcr.microsoft.com/azure-messaging/eventhubs-emulator",
        ["Redis"] = "redis",
        ["Valkey"] = "valkey/valkey",
        ["Garnet"] = "ghcr.io/microsoft/garnet",
        ["Postgres"] = "postgres",
        ["MySql"] = "mysql",
        ["MongoDB"] = "mongo",
        ["RabbitMQ"] = "rabbitmq",
        ["Kafka"] = "confluentinc/confluent-local",
        ["Nats"] = "nats",
        ["Seq"] = "datalust/seq",
        ["Elasticsearch"] = "docker.elastic.co/elasticsearch/elasticsearch",
        ["Qdrant"] = "qdrant/qdrant",
        ["Milvus"] = "milvusdb/milvus",
        ["Oracle"] = "container-registry.oracle.com/database/free",
    };

    /// <summary>Builder dei moduli Testcontainers → repository predefinito.</summary>
    private static readonly Dictionary<string, string> TestcontainersBuilders = new(StringComparer.Ordinal)
    {
        ["MsSqlBuilder"] = "mcr.microsoft.com/mssql/server",
        ["PostgreSqlBuilder"] = "postgres",
        ["RedisBuilder"] = "redis",
        ["AzuriteBuilder"] = "mcr.microsoft.com/azure-storage/azurite",
        ["KeycloakBuilder"] = "quay.io/keycloak/keycloak",
        ["RabbitMqBuilder"] = "rabbitmq",
        ["MongoDbBuilder"] = "mongo",
        ["MySqlBuilder"] = "mysql",
        ["KafkaBuilder"] = "confluentinc/cp-kafka",
        ["ElasticsearchBuilder"] = "docker.elastic.co/elasticsearch/elasticsearch",
    };

    public ProjectReferences Scan(IEnumerable<string> roots, CancellationToken ct)
    {
        List<ImageReference> images = [];
        HashSet<string> composeProjects = new(StringComparer.Ordinal);

        foreach (string file in roots.SelectMany(root => EnumerateFiles(root, ct)))
        {
            ct.ThrowIfCancellationRequested();

            string name = fileSystem.Path.GetFileName(file);
            FileKind kind = Classify(name);
            if (kind == FileKind.None || !TryRead(file, out string text))
            {
                continue;
            }

            switch (kind)
            {
                case FileKind.Compose:
                    images.AddRange(YamlImageLines(file, text));
                    composeProjects.Add(ComposeProjectName(file, text));
                    break;
                case FileKind.Dockerfile:
                    images.AddRange(DockerfileFromLines(file, text));
                    break;
                case FileKind.CSharp:
                    images.AddRange(CSharpReferences(file, text));
                    break;
                case FileKind.Yaml:
                    images.AddRange(YamlImageLines(file, text));
                    images.AddRange(HelmRepositoryTags(file, text));
                    break;
            }
        }

        return new ProjectReferences(images, composeProjects);
    }

    // --- Attraversamento ---------------------------------------------------------------------

    private IEnumerable<string> EnumerateFiles(string root, CancellationToken ct)
    {
        if (!fileSystem.Directory.Exists(root))
        {
            yield break;
        }

        Stack<(string Path, int Depth)> pending = new([(root, 0)]);

        while (pending.Count > 0)
        {
            ct.ThrowIfCancellationRequested();
            (string directory, int depth) = pending.Pop();

            string[] files;
            string[] children;
            try
            {
                files = [.. fileSystem.Directory.EnumerateFiles(directory)];
                children = [.. fileSystem.Directory.EnumerateDirectories(directory)];
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                continue;
            }

            foreach (string file in files)
            {
                yield return file;
            }

            if (depth >= MaxDepth)
            {
                continue;
            }

            foreach (string child in children)
            {
                if (!ExcludedDirectories.Contains(fileSystem.Path.GetFileName(child)) && !IsLink(child))
                {
                    pending.Push((child, depth + 1));
                }
            }
        }
    }

    /// <summary>I collegamenti non si seguono: un link a "/" o a un'altra cartella progetto renderebbe la ricerca lenta o ciclica.</summary>
    private bool IsLink(string directory)
    {
        try
        {
            return fileSystem.File.GetAttributes(directory).HasFlag(FileAttributes.ReparsePoint);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return true;
        }
    }

    private bool TryRead(string file, out string text)
    {
        text = string.Empty;
        try
        {
            if (fileSystem.FileInfo.New(file).Length > MaxFileBytes)
            {
                return false;
            }

            text = fileSystem.File.ReadAllText(file);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private enum FileKind { None, Compose, Dockerfile, CSharp, Yaml }

    private static FileKind Classify(string name)
    {
        if (ComposeFileName().IsMatch(name))
        {
            return FileKind.Compose;
        }

        if (DockerfileName().IsMatch(name))
        {
            return FileKind.Dockerfile;
        }

        if (name.EndsWith(".cs", StringComparison.OrdinalIgnoreCase))
        {
            return FileKind.CSharp;
        }

        return name.EndsWith(".yaml", StringComparison.OrdinalIgnoreCase) || name.EndsWith(".yml", StringComparison.OrdinalIgnoreCase)
            ? FileKind.Yaml
            : FileKind.None;
    }

    // --- YAML (compose, Kubernetes, Helm) ----------------------------------------------------

    private static IEnumerable<ImageReference> YamlImageLines(string file, string text)
    {
        string[] lines = text.Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            Match match = YamlImageLine().Match(lines[i]);
            if (match.Success && Reference(match.Groups["ref"].Value, null, file, i + 1) is { } reference)
            {
                yield return reference;
            }
        }
    }

    /// <summary>Valori Helm: <c>repository:</c> seguito a breve distanza dal suo <c>tag:</c>.</summary>
    private static IEnumerable<ImageReference> HelmRepositoryTags(string file, string text)
    {
        string[] lines = text.Split('\n');
        for (int i = 0; i < lines.Length; i++)
        {
            Match repository = YamlRepositoryLine().Match(lines[i]);
            if (!repository.Success || repository.Groups["value"].Value.Contains("://", StringComparison.Ordinal))
            {
                continue;
            }

            string? tag = lines.Skip(i + 1).Take(4)
                .Select(line => YamlTagLine().Match(line))
                .FirstOrDefault(m => m.Success)?.Groups["value"].Value;

            if (Reference(repository.Groups["value"].Value, tag, file, i + 1) is { } reference)
            {
                yield return reference;
            }
        }
    }

    /// <summary>Il nome che Compose dà al progetto: <c>name:</c> se dichiarato, altrimenti la cartella.</summary>
    private string ComposeProjectName(string file, string text)
    {
        Match declared = ComposeNameLine().Match(text);
        string raw = declared.Success
            ? declared.Groups["value"].Value
            : fileSystem.Path.GetFileName(fileSystem.Path.GetDirectoryName(file)) ?? string.Empty;

        return new string([.. raw.ToLowerInvariant().Where(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-')]);
    }

    // --- Dockerfile --------------------------------------------------------------------------

    private static IEnumerable<ImageReference> DockerfileFromLines(string file, string text)
    {
        HashSet<string> stages = new(StringComparer.OrdinalIgnoreCase) { "scratch" };
        string[] lines = text.Split('\n');

        for (int i = 0; i < lines.Length; i++)
        {
            Match match = DockerfileFrom().Match(lines[i]);
            if (!match.Success)
            {
                continue;
            }

            string image = match.Groups["ref"].Value;
            if (!stages.Contains(image) && Reference(image, null, file, i + 1) is { } reference)
            {
                yield return reference;
            }

            if (match.Groups["alias"].Success)
            {
                stages.Add(match.Groups["alias"].Value);
            }
        }
    }

    // --- C# (AppHost di Aspire, Testcontainers) ----------------------------------------------

    /// <summary>
    /// Per istruzione (testo fra due ";"), non per riga: <c>AddSqlServer("sql")</c> e il suo
    /// <c>.WithImageTag("2025-latest")</c> stanno di solito su righe diverse della stessa catena.
    /// Solo i file che sono un AppHost o usano Testcontainers: un "postgres:16" in una stringa
    /// qualunque non è un riferimento.
    /// </summary>
    private static IEnumerable<ImageReference> CSharpReferences(string file, string text)
    {
        if (!text.Contains("DistributedApplication", StringComparison.Ordinal)
            && !text.Contains("Testcontainers", StringComparison.Ordinal))
        {
            yield break;
        }

        int start = 0;
        while (start < text.Length)
        {
            int end = text.IndexOf(';', start);
            if (end < 0)
            {
                end = text.Length;
            }

            string statement = text[start..end];
            int firstChar = start + (statement.Length - statement.TrimStart().Length);
            int line = 1 + text.AsSpan(0, firstChar).Count('\n');

            if (StatementReference(statement, file, line) is { } reference)
            {
                yield return reference;
            }

            start = end + 1;
        }
    }

    private static ImageReference? StatementReference(string statement, string file, int line)
    {
        string? tagOverride = MatchValue(WithImageTag(), statement, "tag");
        string? registry = MatchValue(WithImageRegistry(), statement, "registry");

        Match explicitImage = new[] { WithImage(), AddContainer(), BuilderWithImage() }
            .Select(pattern => pattern.Match(statement))
            .FirstOrDefault(m => m.Success) ?? Match.Empty;

        string? image;
        string? tag;

        if (explicitImage.Success)
        {
            image = explicitImage.Groups["image"].Value;
            tag = explicitImage.Groups["tag"].Success ? explicitImage.Groups["tag"].Value : tagOverride;
        }
        else
        {
            image = AspireResource().Matches(statement)
                .Select(m => AspireResources.GetValueOrDefault(m.Groups["resource"].Value))
                .FirstOrDefault(repo => repo is not null)
                ?? TestcontainersBuilders.GetValueOrDefault(MatchValue(EmptyBuilder(), statement, "builder") ?? string.Empty);
            tag = tagOverride;
        }

        if (image is null)
        {
            return null;
        }

        if (registry is not null && ImageName.Parse(image).Repository.StartsWith("docker.io/", StringComparison.Ordinal))
        {
            image = $"{registry.TrimEnd('/')}/{image}";
        }

        return Reference(image, tag, file, line);
    }

    private static string? MatchValue(Regex pattern, string text, string group)
    {
        Match match = pattern.Match(text);
        return match.Success ? match.Groups[group].Value : null;
    }

    /// <summary>Valori con template (<c>${TAG}</c>, <c>{{ .Values.image }}</c>) non sono confrontabili: si scartano.</summary>
    private static ImageReference? Reference(string image, string? tag, string file, int line)
    {
        if (string.IsNullOrWhiteSpace(image) || image.Contains('$') || image.Contains('{')
            || (tag is not null && (tag.Contains('$') || tag.Contains('{'))))
        {
            return null;
        }

        ImageName name = ImageName.Parse(image);
        return new ImageReference(name.Repository, tag ?? name.Tag, file, line);
    }

    [GeneratedRegex(@"^(docker-)?compose[\w.-]*\.ya?ml$", RegexOptions.IgnoreCase)]
    private static partial Regex ComposeFileName();

    [GeneratedRegex(@"^((Dockerfile|Containerfile)[\w.-]*|[\w.-]+\.Dockerfile)$", RegexOptions.IgnoreCase)]
    private static partial Regex DockerfileName();

    [GeneratedRegex(@"^\s*(-\s*)?image:\s*[""']?(?<ref>[^""'\s#]+)[""']?\s*(#.*)?\r?$")]
    private static partial Regex YamlImageLine();

    [GeneratedRegex(@"^\s*repository:\s*[""']?(?<value>[^""'\s#]+)[""']?\s*(#.*)?\r?$")]
    private static partial Regex YamlRepositoryLine();

    [GeneratedRegex(@"^\s*tag:\s*[""']?(?<value>[^""'\s#]+)[""']?\s*(#.*)?\r?$")]
    private static partial Regex YamlTagLine();

    [GeneratedRegex(@"^name:\s*[""']?(?<value>[^""'\s#]+)", RegexOptions.Multiline)]
    private static partial Regex ComposeNameLine();

    [GeneratedRegex(@"^\s*FROM\s+(?:--\S+\s+)*(?<ref>\S+)(?:\s+AS\s+(?<alias>\S+))?", RegexOptions.IgnoreCase)]
    private static partial Regex DockerfileFrom();

    [GeneratedRegex(@"\.WithImage\(\s*""(?<image>[^""]+)""(?:\s*,\s*""(?<tag>[^""]+)"")?")]
    private static partial Regex WithImage();

    [GeneratedRegex(@"\.AddContainer\(\s*""[^""]*""\s*,\s*""(?<image>[^""]+)""(?:\s*,\s*""(?<tag>[^""]+)"")?")]
    private static partial Regex AddContainer();

    [GeneratedRegex(@"new\s+\w+Builder\(\s*""(?<image>[^""]+)""")]
    private static partial Regex BuilderWithImage();

    [GeneratedRegex(@"new\s+(?<builder>\w+Builder)\(\s*\)")]
    private static partial Regex EmptyBuilder();

    [GeneratedRegex(@"\.Add(?<resource>\w+)\(")]
    private static partial Regex AspireResource();

    [GeneratedRegex(@"\.WithImageTag\(\s*""(?<tag>[^""]+)""")]
    private static partial Regex WithImageTag();

    [GeneratedRegex(@"\.WithImageRegistry\(\s*""(?<registry>[^""]+)""")]
    private static partial Regex WithImageRegistry();
}
