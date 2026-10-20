import Foundation

/// Dove sta una riga nel risultato di `ConfirmationRows.build`: l'indice del gruppo e quello della
/// riga dentro il gruppo.
public struct ConfirmationPosition: Sendable, Equatable, Hashable {
    public let category: Int
    public let row: Int

    public init(category: Int, row: Int) {
        self.category = category
        self.row = row
    }
}

/// Una riga del passo di conferma. `container` è la riga-cartella più vicina che contiene questa
/// voce, in qualunque gruppo: cancellare quella cartella cancella anche questa voce.
public struct ConfirmationRow: Sendable, Equatable {
    public let item: ScanItem
    public let container: ConfirmationPosition?

    public init(item: ScanItem, container: ConfirmationPosition?) {
        self.item = item
        self.container = container
    }
}

/// Le righe di una categoria dopo la deduplicazione: una categoria il cui contenuto è stato
/// interamente riassorbito da una precedente non compare, non avrebbe righe da mostrare.
public struct ConfirmationCategory: Sendable, Equatable {
    public let categoryId: String
    public let rows: [ConfirmationRow]

    public init(categoryId: String, rows: [ConfirmationRow]) {
        self.categoryId = categoryId
        self.rows = rows
    }

    public var items: [ScanItem] { rows.map(\.item) }
}

/// Le righe del passo di conferma: un percorso, una riga, in tutto il passo; per ogni riga, la
/// cartella proposta che la contiene (spec `2026-10-20-confirmation-containment-design.md`).
public enum ConfirmationRows {
    /// Deduplica GLOBALMENTE: lo stesso percorso proposto da due categorie (cartelle dei file grandi
    /// sovrapposte a una root del catalogo) produceva due righe, il totale lo contava due volte e
    /// deselezionarlo in una categoria non lo escludeva dall'altra. Si tiene il primo incontrato,
    /// nell'ordine dei risultati: stesso file, stessa dimensione.
    ///
    /// Poi lega ogni riga alla riga-cartella più vicina che la contiene, in qualunque gruppo e in
    /// qualunque ordine: con «File grandi» su `~`, un modello sotto `~/.cache/huggingface` sta nella
    /// cartella che «Cache di sviluppo» propone, e cancellarla cancella anche il modello.
    ///
    /// I percorsi si confrontano come li cancellerà il motore: riportati sulla root risolta da
    /// `resolveRoot` (chiamato una volta per root) e ripiegati come APFS. Riconoscere un
    /// contenimento in più è sicuro (la voce appare spuntata e non parte); riconoscerne uno in meno
    /// mostrerebbe deselezionata una voce che la cartella cancella.
    public static func build(_ results: [CategoryScanResult], resolveRoot: (String) -> String) -> [ConfirmationCategory] {
        var resolvedRoots: [[UInt8]: String] = [:]
        func key(_ item: ScanItem) -> String {
            let rootKey = Array(item.declaredRoot.utf8)
            let resolved: String
            if let known = resolvedRoots[rootKey] {
                resolved = known
            } else {
                resolved = resolveRoot(item.declaredRoot)
                resolvedRoots[rootKey] = resolved
            }
            let rewritten = CleanEngine.rewriteToResolvedRoot(item.path, declaredRoot: item.declaredRoot, resolvedRoot: resolved)
            return comparisonKey(rewritten)
        }

        var seenKeys = Set<String>()
        var kept: [(categoryId: String, entries: [(item: ScanItem, key: String)])] = []
        for result in results {
            var entries: [(item: ScanItem, key: String)] = []
            for item in result.items {
                let itemKey = key(item)
                if seenKeys.insert(itemKey).inserted {
                    entries.append((item, itemKey))
                }
            }
            if !entries.isEmpty {
                kept.append((result.categoryId, entries))
            }
        }

        // Solo cartelle e pacchetti contengono: un file non contiene mai nulla.
        var directories: [String: ConfirmationPosition] = [:]
        for (categoryIndex, category) in kept.enumerated() {
            for (rowIndex, entry) in category.entries.enumerated() where entry.item.isDirectory {
                directories[entry.key] = ConfirmationPosition(category: categoryIndex, row: rowIndex)
            }
        }

        return kept.map { category in
            ConfirmationCategory(
                categoryId: category.categoryId,
                rows: category.entries.map { ConfirmationRow(item: $0.item, container: nearestContainer($0.key, directories)) })
        }
    }

    /// Le voci da consegnare al motore: una riga parte se è selezionata e nessuna riga della sua
    /// catena di cartelle lo è. Così la selezione non contiene mai una voce sotto un'altra voce
    /// della stessa selezione: niente byte contati due volte, niente ENOENT su un file già
    /// cancellato con la sua cartella.
    public static func selections(
        _ categories: [ConfirmationCategory],
        isSelected: (ConfirmationPosition) -> Bool
    ) -> [CategorySelection] {
        func isCovered(_ row: ConfirmationRow) -> Bool {
            var next = row.container
            while let position = next {
                if isSelected(position) { return true }
                // Una posizione che non esiste non viene da `build`: la riga non parte, è la
                // direzione sicura.
                guard categories.indices.contains(position.category),
                      categories[position.category].rows.indices.contains(position.row) else { return true }
                next = categories[position.category].rows[position.row].container
            }
            return false
        }

        return categories.enumerated().compactMap { categoryIndex, category in
            let items = category.rows.enumerated()
                .filter { rowIndex, row in
                    isSelected(ConfirmationPosition(category: categoryIndex, row: rowIndex)) && !isCovered(row)
                }
                .map(\.element.item)
            return items.isEmpty ? nil : CategorySelection(categoryId: category.categoryId, items: items)
        }
    }

    /// La chiave di confronto: ripiegamento completo delle maiuscole, come APFS («ß» e «ss», il segno
    /// Kelvin e «k»). Più ampio di `PathText.folded`, che segue OrdinalIgnoreCase per il guard: qui
    /// unire di più è la direzione sicura. Le grafie NFC e NFD non vanno scomposte a parte: chiavi
    /// `String` in `Set` e `Dictionary` si confrontano per equivalenza canonica.
    static func comparisonKey(_ path: String) -> String {
        path.folding(options: [.caseInsensitive], locale: nil)
    }

    /// Risale gli antenati della chiave tagliando all'ultima «/», per scalari: un segmento che
    /// comincia con un segno combinante formerebbe un solo carattere con la «/» che lo precede.
    private static func nearestContainer(_ key: String, _ directories: [String: ConfirmationPosition]) -> ConfirmationPosition? {
        var scalars = key.unicodeScalars[...]
        while let slash = scalars.lastIndex(of: "/") {
            scalars = scalars[..<slash]
            if let position = directories[String(String.UnicodeScalarView(scalars))] {
                return position
            }
        }
        return nil
    }
}
