@testable import CleanerCore

/// Porting di `FakeLinkInspector.cs`. L'inizializzatore a elenco marca ogni percorso come
/// collegamento con destinazione non specificata (`resolveLinkTarget` → `nil`); quello a mappa
/// indica la destinazione finale. Confronto senza distinzione fra maiuscole e minuscole, come
/// il dizionario `OrdinalIgnoreCase` del C#.
struct FakeLinkInspector: LinkInspecting {
    private let links: [String: String?]

    init(_ links: String...) {
        self.init(links)
    }

    init(_ links: [String]) {
        var map: [String: String?] = [:]
        for link in links { map[Self.key(link)] = .some(nil) }
        self.links = map
    }

    init(targets: [String: String?]) {
        var map: [String: String?] = [:]
        for (link, target) in targets { map[Self.key(link)] = .some(target) }
        self.links = map
    }

    func isSymbolicLink(_ path: String) -> Bool {
        links[Self.key(path)] != nil
    }

    func resolveLinkTarget(_ path: String) -> String? {
        links[Self.key(path)] ?? nil
    }

    private static func key(_ path: String) -> String {
        PathText.folded(PathText.trimmingTrailingSlashes(path))
    }
}
