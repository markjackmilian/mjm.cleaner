/// Riferimento a un'immagine ridotto a repository normalizzato e tag. Docker mostra lo stesso
/// repository in forme diverse ("alpine", "docker.io/library/alpine"): confrontare le stringhe
/// grezze farebbe sembrare diverse due immagini identiche, e una regola come "versione superata" o
/// "citata nei progetti" non scatterebbe mai.
public struct ImageName: Sendable, Equatable, Hashable {
    private static let defaultRegistry = "docker.io"

    public let repository: String
    public let tag: String?

    public init(repository: String, tag: String?) {
        self.repository = repository
        self.tag = tag
    }

    /// Ultimo segmento del repository: "testcontainers/ryuk" → "ryuk".
    public var shortName: String { PathText.fileName(repository) }

    /// I separatori "@", ":" e "/" sono ASCII: si cercano e si taglia sui byte UTF-8, come gli
    /// `IndexOf`/`LastIndexOf` del C# sulle unità UTF-16.
    public static func parse(_ reference: String) -> ImageName {
        var value = Array(DockerText.trimmed(reference).utf8)

        // Il digest identifica il contenuto, non il nome: per il confronto conta solo repository:tag.
        if let at = value.firstIndex(of: UInt8(ascii: "@")) {
            value = Array(value.prefix(upTo: at))
        }

        // Il tag è dopo l'ultimo ":" che segue l'ultimo "/": in "localhost:5000/app" i due punti
        // appartengono al registro, non al tag.
        var tag: String?
        let slash = value.lastIndex(of: UInt8(ascii: "/")) ?? -1
        if let colon = value.lastIndex(of: UInt8(ascii: ":")), colon > slash {
            tag = String(decoding: value.suffix(from: colon + 1), as: UTF8.self)
            value = Array(value.prefix(upTo: colon))
        }

        let repository = normalizeRepository(String(decoding: value, as: UTF8.self))
        return ImageName(repository: repository, tag: tag?.isEmpty == false ? tag : nil)
    }

    private static func normalizeRepository(_ repository: String) -> String {
        let lower = DockerText.lowercasedInvariant(repository)
        let bytes = Array(lower.utf8)

        guard let slash = bytes.firstIndex(of: UInt8(ascii: "/")) else {
            return "\(defaultRegistry)/library/\(lower)"
        }

        let first = bytes.prefix(upTo: slash)
        let hasRegistry = first.contains(UInt8(ascii: "."))
            || first.contains(UInt8(ascii: ":"))
            || first.elementsEqual("localhost".utf8)

        return hasRegistry ? lower : "\(defaultRegistry)/\(lower)"
    }
}
