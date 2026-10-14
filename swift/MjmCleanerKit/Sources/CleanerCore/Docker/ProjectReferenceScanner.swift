/// Cerca nei file dei progetti le immagini che vi sono citate: un'immagine che un compose, un
/// Dockerfile o un AppHost useranno al prossimo avvio non va proposta per la cancellazione solo
/// perché oggi nessun container la usa. Regex per riga o per istruzione, non un parser YAML/C#: deve
/// restare veloce su un'intera cartella di progetti, e un riferimento mancato costa al massimo una
/// voce PROPOSE che l'utente vede e può lasciare deselezionata.
///
/// Le regex sono il porting di quelle generate del C# con la semantica di .NET 10 (misurata durante
/// la stesura del piano 2): corrispondenza per scalare (`.unicodeScalar`), `.` di .NET come `[^\n]`,
/// `\w` di .NET come `[[\p{L}\p{Mn}\p{Nd}\p{Pc}]&&[\x{0}-\x{FFFF}]]`, `$` di .NET come `\n?$`, e
/// per `IgnoreCase` la "i" anche come U+0130, che .NET le equipara e Swift no. `Regex` non è
/// `Sendable`: le regex si costruiscono a ogni ricerca, una volta per file.
public struct ProjectReferenceScanner: Sendable {
    private static let maxFileBytes: Int64 = 1024 * 1024
    private static let maxDepth = 12

    /// Confronto `OrdinalIgnoreCase`: i nomi sono già ripiegati, come le chiavi cercate.
    private static let excludedDirectories = Set([
        "node_modules", "bin", "obj", ".git", ".hg", ".svn", ".vs", ".idea", "packages",
        ".venv", "venv", "__pycache__", "dist", "target", ".gradle", "Pods", "DerivedData",
    ].map(PathText.folded))

    /// Metodi di hosting di .NET Aspire → repository dell'immagine che avviano.
    private static let aspireResources: [String: String] = [
        "SqlServer": "mcr.microsoft.com/mssql/server",
        "Keycloak": "quay.io/keycloak/keycloak",
        "AzureStorage": "mcr.microsoft.com/azure-storage/azurite",
        "AzureCosmosDB": "mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator",
        "AzureServiceBus": "mcr.microsoft.com/azure-messaging/servicebus-emulator",
        "AzureEventHubs": "mcr.microsoft.com/azure-messaging/eventhubs-emulator",
        "Redis": "redis",
        "Valkey": "valkey/valkey",
        "Garnet": "ghcr.io/microsoft/garnet",
        "Postgres": "postgres",
        "MySql": "mysql",
        "MongoDB": "mongo",
        "RabbitMQ": "rabbitmq",
        "Kafka": "confluentinc/confluent-local",
        "Nats": "nats",
        "Seq": "datalust/seq",
        "Elasticsearch": "docker.elastic.co/elasticsearch/elasticsearch",
        "Qdrant": "qdrant/qdrant",
        "Milvus": "milvusdb/milvus",
        "Oracle": "container-registry.oracle.com/database/free",
    ]

    /// Builder dei moduli Testcontainers → repository predefinito.
    private static let testcontainersBuilders: [String: String] = [
        "MsSqlBuilder": "mcr.microsoft.com/mssql/server",
        "PostgreSqlBuilder": "postgres",
        "RedisBuilder": "redis",
        "AzuriteBuilder": "mcr.microsoft.com/azure-storage/azurite",
        "KeycloakBuilder": "quay.io/keycloak/keycloak",
        "RabbitMqBuilder": "rabbitmq",
        "MongoDbBuilder": "mongo",
        "MySqlBuilder": "mysql",
        "KafkaBuilder": "confluentinc/cp-kafka",
        "ElasticsearchBuilder": "docker.elastic.co/elasticsearch/elasticsearch",
    ]

    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    /// Lancia solo `CancellationError`. Sincrona come in C#: chi la chiama da codice asincrono la
    /// esegue fuori dal proprio executor (`DockerCleanupService.analyze`).
    public func scan(_ roots: [String]) throws -> ProjectReferences {
        var images: [ImageReference] = []
        var composeProjects = Set<String>()

        for root in roots {
            try forEachFile(under: root) { file in
                try Task.checkCancellation()

                let kind = Self.classify(PathText.fileName(file))
                guard kind != .none, let text = read(file) else { return }

                switch kind {
                case .compose:
                    images += Self.yamlImageLines(file, text)
                    composeProjects.insert(composeProjectName(file, text))
                case .dockerfile:
                    images += Self.dockerfileFromLines(file, text)
                case .cSharp:
                    images += Self.cSharpReferences(file, text)
                case .yaml:
                    images += Self.yamlImageLines(file, text)
                    images += Self.helmRepositoryTags(file, text)
                case .none:
                    break
                }
            }
        }

        return ProjectReferences(images: images, composeProjects: composeProjects)
    }

    // MARK: - Attraversamento

    /// Visita in profondità con una pila esplicita, come il C#: i file di una cartella, poi le
    /// sottocartelle in ordine inverso. L'elenco di una cartella è in ordine ordinale (il C# seguiva
    /// l'ordine di `readdir`, che non è garantito).
    private func forEachFile(under root: String, _ visit: (String) throws -> Void) throws {
        guard fileSystem.directoryExists(root) else { return }

        var pending: [(path: String, depth: Int)] = [(root, 0)]

        while let (directory, depth) = pending.popLast() {
            try Task.checkCancellation()

            let entries: [String]
            do {
                entries = try fileSystem.contentsOfDirectory(directory)
            } catch is FileSystemError {
                continue
            }

            // Come `EnumerateFiles`/`EnumerateDirectories`: un collegamento a una cartella conta
            // come cartella (e poi si scarta sotto), tutto il resto come file.
            let children = entries.filter(fileSystem.directoryExists)
            for file in entries where !fileSystem.directoryExists(file) {
                try visit(file)
            }

            if depth >= Self.maxDepth {
                continue
            }

            for child in children where !Self.excludedDirectories.contains(PathText.folded(PathText.fileName(child))) && !isLink(child) {
                pending.append((child, depth + 1))
            }
        }
    }

    /// I collegamenti non si seguono: un link a "/" o a un'altra cartella progetto renderebbe la
    /// ricerca lenta o ciclica.
    private func isLink(_ directory: String) -> Bool {
        do {
            return try fileSystem.itemInfo(directory).kind == .symbolicLink
        } catch {
            return true
        }
    }

    /// Come `FileInfo.Length` (del collegamento stesso, `lstat`) e poi `File.ReadAllText`.
    private func read(_ file: String) -> String? {
        do {
            if try fileSystem.fileLength(file) > Self.maxFileBytes {
                return nil
            }
            return DockerText.decodeLikeReadAllText(try fileSystem.readData(file))
        } catch {
            return nil
        }
    }

    private enum FileKind {
        case none
        case compose
        case dockerfile
        case cSharp
        case yaml
    }

    private static func classify(_ name: String) -> FileKind {
        // `^(docker-)?compose[\w.-]*\.ya?ml$`, IgnoreCase.
        let composeFileName = /^(?:docker-)?compose[[\p{L}\p{Mn}\p{Nd}\p{Pc}.\-]&&[\x{0}-\x{FFFF}]]*\.ya?ml\n?$/
            .ignoresCase()
            .matchingSemantics(.unicodeScalar)
        // `^((Dockerfile|Containerfile)[\w.-]*|[\w.-]+\.Dockerfile)$`, IgnoreCase.
        let dockerfileName = /^(?:(?:Dockerfile|Containerfile)[[\p{L}\p{Mn}\p{Nd}\p{Pc}.\-]&&[\x{0}-\x{FFFF}]]*|[[\p{L}\p{Mn}\p{Nd}\p{Pc}.\-]&&[\x{0}-\x{FFFF}]]+\.Dockerfile)\n?$/
            .ignoresCase()
            .matchingSemantics(.unicodeScalar)

        if name.firstMatch(of: composeFileName) != nil {
            return .compose
        }

        if name.firstMatch(of: dockerfileName) != nil {
            return .dockerfile
        }

        if DockerText.hasSuffixIgnoringCase(name, ".cs") {
            return .cSharp
        }

        return DockerText.hasSuffixIgnoringCase(name, ".yaml") || DockerText.hasSuffixIgnoringCase(name, ".yml") ? .yaml : .none
    }

    // MARK: - YAML (compose, Kubernetes, Helm)

    // Le righe sono già divise su "\n": il "$" di .NET non ha un "\n" finale da accettare.

    private static func yamlImageLines(_ file: String, _ text: String) -> [ImageReference] {
        let yamlImageLine = /^\s*(?:-\s*)?image:\s*["']?(?<ref>[^"'\s#]+)["']?\s*(?:#[^\n]*)?\r?$/
            .matchingSemantics(.unicodeScalar)

        var references: [ImageReference] = []
        for (index, line) in DockerText.rawLines(text).enumerated() {
            if let match = line.firstMatch(of: yamlImageLine),
               let reference = reference(String(match.output.ref), nil, file, index + 1) {
                references.append(reference)
            }
        }
        return references
    }

    /// Valori Helm: `repository:` seguito a breve distanza dal suo `tag:`.
    private static func helmRepositoryTags(_ file: String, _ text: String) -> [ImageReference] {
        let yamlRepositoryLine = /^\s*repository:\s*["']?(?<value>[^"'\s#]+)["']?\s*(?:#[^\n]*)?\r?$/
            .matchingSemantics(.unicodeScalar)
        let yamlTagLine = /^\s*tag:\s*["']?(?<value>[^"'\s#]+)["']?\s*(?:#[^\n]*)?\r?$/
            .matchingSemantics(.unicodeScalar)

        let lines = DockerText.rawLines(text)
        var references: [ImageReference] = []
        for (index, line) in lines.enumerated() {
            guard let repository = line.firstMatch(of: yamlRepositoryLine),
                  !DockerText.contains(String(repository.output.value), "://") else {
                continue
            }

            let tag = lines.dropFirst(index + 1).prefix(4)
                .lazy
                .compactMap { $0.firstMatch(of: yamlTagLine) }
                .first
                .map { String($0.output.value) }

            if let reference = reference(String(repository.output.value), tag, file, index + 1) {
                references.append(reference)
            }
        }
        return references
    }

    /// Il nome che Compose dà al progetto: `name:` se dichiarato, altrimenti la cartella.
    private func composeProjectName(_ file: String, _ text: String) -> String {
        // `^name:\s*["']?(?<value>[^"'\s#]+)` con `RegexOptions.Multiline`: "^" vale all'inizio del
        // testo e dopo ogni "\n", e solo lì; `\s*` può proseguire sulle righe seguenti.
        let composeNameLine = /name:\s*["']?(?<value>[^"'\s#]+)/
            .matchingSemantics(.unicodeScalar)

        let declared = DockerText.lineStarts(text).lazy
            .compactMap { text[$0...].prefixMatch(of: composeNameLine) }
            .first
            .map { String($0.output.value) }
        let raw = declared ?? PathText.parent(file).map(PathText.fileName) ?? ""

        var name = String.UnicodeScalarView()
        for scalar in DockerText.lowercasedInvariant(raw).unicodeScalars
        where scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-") {
            name.append(scalar)
        }
        return String(name)
    }

    // MARK: - Dockerfile

    private static func dockerfileFromLines(_ file: String, _ text: String) -> [ImageReference] {
        // `^\s*FROM\s+(?:--\S+\s+)*(?<ref>\S+)(?:\s+AS\s+(?<alias>\S+))?`, IgnoreCase: "FROM" e "AS"
        // non hanno la "i" né la "k", quindi `ignoresCase` di Swift coincide con .NET.
        let dockerfileFrom = /^\s*FROM\s+(?:--\S+\s+)*(?<ref>\S+)(?:\s+AS\s+(?<alias>\S+))?/
            .ignoresCase()
            .matchingSemantics(.unicodeScalar)

        // `HashSet(StringComparer.OrdinalIgnoreCase)`: si conservano i nomi ripiegati.
        var stages: Set<String> = [PathText.folded("scratch")]
        var references: [ImageReference] = []

        for (index, line) in DockerText.rawLines(text).enumerated() {
            guard let match = line.firstMatch(of: dockerfileFrom) else { continue }

            let image = String(match.output.ref)
            if !stages.contains(PathText.folded(image)), let reference = reference(image, nil, file, index + 1) {
                references.append(reference)
            }

            if let alias = match.output.alias {
                stages.insert(PathText.folded(String(alias)))
            }
        }
        return references
    }

    // MARK: - C# (AppHost di Aspire, Testcontainers)

    /// Per istruzione (testo fra due ";"), non per riga: `AddSqlServer("sql")` e il suo
    /// `.WithImageTag("2025-latest")` stanno di solito su righe diverse della stessa catena. Solo i
    /// file che sono un AppHost o usano Testcontainers: un "postgres:16" in una stringa qualunque non
    /// è un riferimento.
    private static func cSharpReferences(_ file: String, _ text: String) -> [ImageReference] {
        guard DockerText.contains(text, "DistributedApplication") || DockerText.contains(text, "Testcontainers") else {
            return []
        }

        let withImageTag = /\.WithImageTag\(\s*"(?<tag>[^"]+)"/.matchingSemantics(.unicodeScalar)
        let withImageRegistry = /\.WithImageRegistry\(\s*"(?<registry>[^"]+)"/.matchingSemantics(.unicodeScalar)
        let withImage = /\.WithImage\(\s*"(?<image>[^"]+)"(?:\s*,\s*"(?<tag>[^"]+)")?/.matchingSemantics(.unicodeScalar)
        let addContainer = /\.AddContainer\(\s*"[^"]*"\s*,\s*"(?<image>[^"]+)"(?:\s*,\s*"(?<tag>[^"]+)")?/.matchingSemantics(.unicodeScalar)
        let builderWithImage = /new\s+[[\p{L}\p{Mn}\p{Nd}\p{Pc}]&&[\x{0}-\x{FFFF}]]+Builder\(\s*"(?<image>[^"]+)"/.matchingSemantics(.unicodeScalar)
        let emptyBuilder = /new\s+(?<builder>[[\p{L}\p{Mn}\p{Nd}\p{Pc}]&&[\x{0}-\x{FFFF}]]+Builder)\(\s*\)/.matchingSemantics(.unicodeScalar)
        let aspireResource = /\.Add(?<resource>[[\p{L}\p{Mn}\p{Nd}\p{Pc}]&&[\x{0}-\x{FFFF}]]+)\(/.matchingSemantics(.unicodeScalar)

        func statementReference(_ statement: Substring, line: Int) -> ImageReference? {
            let tagOverride = statement.firstMatch(of: withImageTag).map { String($0.output.tag) }
            let registry = statement.firstMatch(of: withImageRegistry).map { String($0.output.registry) }

            let explicitImage: (image: Substring, tag: Substring?)? =
                statement.firstMatch(of: withImage).map { ($0.output.image, $0.output.tag) }
                ?? statement.firstMatch(of: addContainer).map { ($0.output.image, $0.output.tag) }
                ?? statement.firstMatch(of: builderWithImage).map { ($0.output.image, nil) }

            var image: String?
            let tag: String?

            if let explicitImage {
                image = String(explicitImage.image)
                tag = explicitImage.tag.map(String.init) ?? tagOverride
            } else {
                image = statement.matches(of: aspireResource).lazy
                    .compactMap { aspireResources[String($0.output.resource)] }
                    .first
                    ?? statement.firstMatch(of: emptyBuilder).flatMap { testcontainersBuilders[String($0.output.builder)] }
                tag = tagOverride
            }

            guard var image else { return nil }

            if let registry, DockerText.hasPrefix(ImageName.parse(image).repository, "docker.io/") {
                image = "\(DockerText.trimmedTrailing(registry, "/"))/\(image)"
            }

            return reference(image, tag, file, line)
        }

        var references: [ImageReference] = []
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        var line = 1

        while start < scalars.endIndex {
            let end = scalars[start...].firstIndex(of: ";") ?? scalars.endIndex
            let statement = Substring(scalars[start..<end])

            // Riga del primo carattere non bianco dell'istruzione: `text.AsSpan(0, firstChar).Count('\n')`.
            let firstChar = scalars[start..<end].firstIndex { !$0.properties.isWhitespace } ?? end
            let statementLine = line + scalars[start..<firstChar].filter { $0 == "\n" }.count

            if let reference = statementReference(statement, line: statementLine) {
                references.append(reference)
            }

            line += scalars[start..<end].filter { $0 == "\n" }.count
            start = end < scalars.endIndex ? scalars.index(after: end) : end
        }

        return references
    }

    /// Valori con template (`${TAG}`, `{{ .Values.image }}`) non sono confrontabili: si scartano.
    private static func reference(_ image: String, _ tag: String?, _ file: String, _ line: Int) -> ImageReference? {
        if DockerText.isBlank(image) || DockerText.contains(image, "$") || DockerText.contains(image, "{") {
            return nil
        }
        if let tag, DockerText.contains(tag, "$") || DockerText.contains(tag, "{") {
            return nil
        }

        let name = ImageName.parse(image)
        return ImageReference(repository: name.repository, tag: tag ?? name.tag, file: file, line: line)
    }
}
