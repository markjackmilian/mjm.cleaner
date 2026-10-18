/// Gli elementi di una categoria dopo la deduplicazione: una categoria il cui contenuto è stato
/// interamente riassorbito da una precedente non compare, non avrebbe righe da mostrare.
public struct ConfirmationCategory: Sendable, Equatable {
    public let categoryId: String
    public let items: [ScanItem]

    public init(categoryId: String, items: [ScanItem]) {
        self.categoryId = categoryId
        self.items = items
    }
}

/// Le righe del passo di conferma: un percorso, una riga, in tutto il passo.
public enum ConfirmationRows {
    /// Deduplica GLOBALMENTE per percorso (equivalenza canonica di String: le grafie NFC e NFD dello
    /// stesso file sono un solo percorso, che APFS risolve allo stesso file): lo stesso percorso proposto da due
    /// categorie (cartelle dei file grandi sovrapposte a una root del catalogo) produceva due righe,
    /// il totale lo contava due volte e deselezionarlo in una categoria non lo escludeva dall'altra.
    /// Si tiene il primo incontrato, nell'ordine del catalogo: stesso file, stessa dimensione.
    public static func build(_ results: [CategoryScanResult]) -> [ConfirmationCategory] {
        var seenPaths = Set<String>()
        var categories: [ConfirmationCategory] = []

        for result in results {
            let items = result.items.filter { seenPaths.insert($0.path).inserted }
            if !items.isEmpty {
                categories.append(ConfirmationCategory(categoryId: result.categoryId, items: items))
            }
        }

        return categories
    }
}
