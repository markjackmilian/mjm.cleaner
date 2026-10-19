import Foundation

/// L'output della CLI non è nel formato atteso: nessuna classificazione è possibile. Porting di
/// `DockerOutputException`.
public struct DockerOutputError: Error, Equatable, Sendable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Dimensioni che solo `docker system df -v` conosce: esclusiva per immagine, totale per volume.
public struct DockerDfVerbose: Sendable, Equatable {
    public let imageUniqueSizes: [String: Int64]
    public let volumeSizes: [String: Int64]

    public init(imageUniqueSizes: [String: Int64], volumeSizes: [String: Int64]) {
        self.imageUniqueSizes = imageUniqueSizes
        self.volumeSizes = volumeSizes
    }
}

/// Parsing puro dell'output JSON della CLI, mai delle tabelle: le colonne cambiano larghezza e
/// ordine fra le versioni, il JSON no. Tollerante verso campi assenti o `null` — misurato:
/// `Config.Labels` manca del tutto su alcune immagini (azurelinux) e `Labels` di un volume senza
/// etichette è `null`, non un oggetto vuoto.
public enum DockerJson {
    public static func parseContainers(_ inspectJson: String) throws -> [DockerContainer] {
        try parseArray(inspectJson, "container") { element in
            let state = child(element, "State")
            return DockerContainer(
                id: string(element, "Id") ?? "",
                name: DockerText.trimmedLeading(string(element, "Name") ?? "", "/"),
                imageId: string(element, "Image") ?? "",
                state: string(state, "Status") ?? "",
                exitCode: integer(child(state, "ExitCode")).flatMap { Int32(exactly: $0) }.map(Int.init) ?? 0,
                volumeNames: items(element, "Mounts")
                    .filter { string($0, "Type") == "volume" }
                    .compactMap { string($0, "Name") },
                labels: labels(child(element, "Config")))
        }
    }

    public static func parseImages(_ inspectJson: String, uniqueSizes: [String: Int64]? = nil) throws -> [DockerImage] {
        try parseArray(inspectJson, "immagine") { element in
            let id = string(element, "Id") ?? ""
            return DockerImage(
                id: id,
                repoTags: strings(element, "RepoTags"),
                repoDigests: strings(element, "RepoDigests"),
                sizeBytes: integer(child(element, "Size")) ?? 0,
                uniqueSizeBytes: uniqueSizes?[id],
                labels: labels(child(element, "Config")),
                origin: origin(child(element, "Identity")))
        }
    }

    public static func parseVolumes(_ inspectJson: String, sizes: [String: Int64]? = nil) throws -> [DockerVolume] {
        try parseArray(inspectJson, "volume") { element in
            let name = string(element, "Name") ?? ""
            return DockerVolume(name: name, labels: labels(element), sizeBytes: sizes?[name])
        }
    }

    public static func parseDfVerbose(_ json: String) throws -> DockerDfVerbose {
        let root = try parse(json, "docker system df -v")
        return DockerDfVerbose(
            imageUniqueSizes: sizes(root, "Images", key: "ID", size: "UniqueSize"),
            volumeSizes: sizes(root, "Volumes", key: "Name", size: "Size"))
    }

    /// Una riga JSON per tipo di risorsa: `docker system df --format '{{json .}}'`.
    public static func parseDfSummary(_ jsonLines: String) throws -> DockerDfSummary {
        DockerDfSummary(entries: try parseJsonLines(jsonLines, "docker system df").map { line in
            DockerDfEntry(
                type: string(line, "Type") ?? "",
                sizeBytes: DockerSize.parse(string(line, "Size")) ?? 0,
                reclaimableBytes: DockerSize.parse(string(line, "Reclaimable")) ?? 0)
        })
    }

    /// `docker info --format` con l'oggetto di `DockerInventoryCollector.engineFormat`. Campi
    /// assenti o `null` valgono stringa vuota.
    public static func parseEngineInfo(_ json: String) throws -> (serverVersion: String, operatingSystem: String) {
        let root = try parse(json, "docker info")
        return (string(root, "ServerVersion") ?? "", string(root, "OperatingSystem") ?? "")
    }

    /// `docker context inspect --format {{json .}}`: nome, descrizione ed endpoint Docker. Campi
    /// assenti valgono stringa vuota (il contesto `default` non ha descrizione).
    public static func parseContext(_ json: String) throws -> DockerContext {
        let root = try parse(json, "docker context inspect")
        return DockerContext(
            name: string(root, "Name") ?? "",
            description: string(child(root, "Metadata"), "Description") ?? "",
            host: string(child(child(root, "Endpoints"), "docker"), "Host") ?? "")
    }

    /// Un valore per riga: `docker ps -aq`.
    public static func parseLines(_ output: String) -> [String] {
        DockerText.distinct(DockerText.lines(output))
    }

    /// Un campo da ciascuna riga di un output `--format '{{json .}}'`.
    public static func parseJsonLinesProperty(_ jsonLines: String, _ property: String) throws -> [String] {
        DockerText.distinct(try parseJsonLines(jsonLines, property).compactMap { string($0, property) })
    }

    // MARK: - Utilità

    private static func parseArray<T>(_ json: String, _ what: String, _ map: (DockerJsonValue) -> T) throws -> [T] {
        guard case .array(let elements) = try parse(json, what) else {
            throw DockerOutputError(String(localized: "Risposta di Docker inattesa per \(what): atteso un elenco JSON.", bundle: .module))
        }
        return elements.map(map)
    }

    private static func parseJsonLines(_ jsonLines: String, _ what: String) throws -> [DockerJsonValue] {
        try DockerText.lines(jsonLines).map { try parse($0, what) }
    }

    private static func parse(_ json: String, _ what: String) throws -> DockerJsonValue {
        do {
            return try JSONDecoder().decode(DockerJsonValue.self, from: Data(json.utf8))
        } catch {
            throw DockerOutputError(String(localized: "Risposta di Docker non leggibile per \(what).", bundle: .module))
        }
    }

    private static func sizes(_ root: DockerJsonValue, _ array: String, key: String, size: String) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for item in items(root, array) {
            if let id = string(item, key), let bytes = DockerSize.parse(string(item, size)) {
                sizes[id] = bytes
            }
        }
        return sizes
    }

    private static func origin(_ identity: DockerJsonValue?) -> ImageOrigin {
        guard let identity else { return .unknown }

        // Pull vince su Build: un'immagine scaricata e poi ritaggata da una build resta
        // riscaricabile, che è ciò che la regola "costruita in locale" vuole sapere.
        if !items(identity, "Pull").isEmpty {
            return .pulled
        }

        return items(identity, "Build").isEmpty ? .unknown : .built
    }

    private static func labels(_ owner: DockerJsonValue?) -> [String: String] {
        guard case .object(let members)? = child(owner, "Labels") else { return [:] }

        var labels: [String: String] = [:]
        for (name, value) in members {
            if case .string(let text) = value { labels[name] = text }
        }
        return labels
    }

    /// Il campo `name` di un oggetto, se presente e non `null`.
    private static func child(_ owner: DockerJsonValue?, _ name: String) -> DockerJsonValue? {
        guard case .object(let members)? = owner, let value = members[name] else { return nil }
        if case .null = value { return nil }
        return value
    }

    private static func string(_ owner: DockerJsonValue?, _ name: String) -> String? {
        guard case .string(let text)? = child(owner, name) else { return nil }
        return text
    }

    /// Un numero intero rappresentabile in 64 bit, come `TryGetInt64`.
    private static func integer(_ value: DockerJsonValue?) -> Int64? {
        guard case .number(let integer)? = value else { return nil }
        return integer
    }

    private static func items(_ owner: DockerJsonValue?, _ name: String) -> [DockerJsonValue] {
        guard case .array(let values)? = child(owner, name) else { return [] }
        return values
    }

    private static func strings(_ owner: DockerJsonValue, _ name: String) -> [String] {
        items(owner, name).compactMap { value in
            guard case .string(let text) = value else { return nil }
            return text
        }
    }
}

/// Un documento JSON con le stesse categorie di `JsonValueKind`: la lettura tollerante del C#
/// esamina i campi uno per uno e ignora quelli del tipo sbagliato, cosa che un `Codable`
/// dichiarativo non consente.
enum DockerJsonValue: Decodable, Equatable {
    case object([String: DockerJsonValue])
    case array([DockerJsonValue])
    case string(String)
    /// Un numero: il valore se è un intero a 64 bit (come `TryGetInt64`), altrimenti `nil`.
    case number(Int64?)
    case bool
    case null

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    init(from decoder: any Decoder) throws {
        if let object = try? decoder.container(keyedBy: Key.self) {
            var members: [String: DockerJsonValue] = [:]
            for key in object.allKeys {
                members[key.stringValue] = try object.decode(DockerJsonValue.self, forKey: key)
            }
            self = .object(members)
        } else if var array = try? decoder.unkeyedContainer() {
            var values: [DockerJsonValue] = []
            while !array.isAtEnd {
                values.append(try array.decode(DockerJsonValue.self))
            }
            self = .array(values)
        } else {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() {
                self = .null
            } else if (try? value.decode(Bool.self)) != nil {
                self = .bool
            } else if let integer = try? value.decode(Int64.self) {
                self = .number(integer)
            } else if (try? value.decode(Double.self)) != nil {
                self = .number(nil)
            } else {
                self = .string(try value.decode(String.self))
            }
        }
    }
}
