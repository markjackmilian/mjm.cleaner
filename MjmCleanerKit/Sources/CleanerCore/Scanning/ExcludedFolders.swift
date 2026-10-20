/// Le cartelle escluse nelle Impostazioni, viste da una regola. Un percorso si confronta in due
/// forme: quella testuale, sotto la root dichiarata, e quella con la root risolta da
/// `validateRoot`. Così un'esclusione scritta "/private/var/…" vale anche per la root `$TMPDIR`,
/// che sta sotto il collegamento "/var". Il confronto ignora le maiuscole, come la deny-list.
///
/// «/» si riduce alla stringa vuota, e `isSameOrUnder(path, "")` è vero per ogni percorso
/// assoluto: escludere la radice esclude tutto, che è la direzione sicura.
struct ExcludedFolders: Sendable {
    private let folders: [String]
    private let root: String
    private let resolvedRoot: String

    init(_ folders: [String], root: String, resolvedRoot: String) {
        self.folders = folders.map(PathText.trimmingTrailingSlashes)
        self.root = PathText.trimmingTrailingSlashes(root)
        self.resolvedRoot = PathText.trimmingTrailingSlashes(resolvedRoot)
    }

    static var excludedReason: String {
        String(localized: "cartella esclusa nelle Impostazioni", bundle: .module)
    }

    static var containsReason: String {
        String(localized: "contiene una cartella esclusa nelle Impostazioni", bundle: .module)
    }

    /// Il motivo per non entrare in una cartella e non proporla: coincide con una cartella esclusa
    /// o sta sotto una di esse. `nil` se nessuna esclusione la riguarda.
    func excludedReason(_ path: String) -> String? {
        let excluded = forms(path).contains { form in
            folders.contains { PathText.isSameOrUnder(form, $0) }
        }
        return excluded ? Self.excludedReason : nil
    }

    /// Il motivo per non proporre un candidato: oltre ai casi di `excludedReason`, una cartella
    /// esclusa sta sotto di lui, ed eliminarlo cancellerebbe anche quella.
    func candidateReason(_ path: String) -> String? {
        if let reason = excludedReason(path) { return reason }
        let containsExcluded = forms(path).contains { form in
            folders.contains { PathText.hasPrefixIgnoringCase($0, form + "/") }
        }
        return containsExcluded ? Self.containsReason : nil
    }

    /// Il percorso com'è e, se sta sotto la root testuale e la root risolta è diversa, lo stesso
    /// percorso sotto la root risolta. Un prefisso riconosciuto senza maiuscole occupa lo stesso
    /// numero di scalari della root (`PathText.hasPrefixIgnoringCase`).
    private func forms(_ path: String) -> [String] {
        guard !resolvedRoot.isEmpty, !PathText.equalsIgnoringCase(root, resolvedRoot), PathText.isSameOrUnder(path, root) else {
            return [path]
        }
        var resolved = String.UnicodeScalarView()
        resolved.append(contentsOf: resolvedRoot.unicodeScalars)
        resolved.append(contentsOf: path.unicodeScalars.dropFirst(root.unicodeScalars.count))
        return [path, String(resolved)]
    }
}
