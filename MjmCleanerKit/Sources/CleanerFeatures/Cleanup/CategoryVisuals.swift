import CleanerCore

/// Tile colorata e simbolo di una categoria, come nel redesign. Il colore vive nel catalogo asset
/// dell'app con le varianti chiaro/scuro (spec §6.4): qui c'è il nome dell'asset e il colore del
/// progetto nella variante chiara, da cui l'asset si costruisce.
public struct CategoryVisual: Sendable, Equatable {
    public let tileColorName: String
    public let designHex: String
    public let symbolName: String
}

public enum CategoryVisuals {
    /// ID sconosciuti ricevono la tile neutra, la stessa dei log.
    public static func visual(for categoryId: String) -> CategoryVisual {
        switch Array(categoryId.utf8) {
        case Array("system-caches".utf8): CategoryVisual(tileColorName: "TileSystemCaches", designHex: "#66788F", symbolName: "internaldrive")
        case Array("dev-caches".utf8): CategoryVisual(tileColorName: "TileDevCaches", designHex: "#7457E8", symbolName: "chevron.left.forwardslash.chevron.right")
        case Array("nuget-packages".utf8): CategoryVisual(tileColorName: "TileNuGet", designHex: "#3567D0", symbolName: "shippingbox")
        case Array("project-build-output".utf8): CategoryVisual(tileColorName: "TileBuildOutput", designHex: "#1D8784", symbolName: "folder")
        case Array("trash".utf8): CategoryVisual(tileColorName: "TileTrash", designHex: "#D2453A", symbolName: "trash")
        case Array("downloads".utf8): CategoryVisual(tileColorName: "TileDownloads", designHex: "#E8833A", symbolName: "arrow.down.to.line")
        case Array("large-files".utf8): CategoryVisual(tileColorName: "TileLargeFiles", designHex: "#B5477F", symbolName: "scalemass")
        default: CategoryVisual(tileColorName: "TileNeutral", designHex: "#85858B", symbolName: "doc.text")
        }
    }
}

extension RiskLevel {
    /// Il testo della pill: il rischio resta comunicato anche senza il colore (spec §6.6).
    public var label: String {
        switch self {
        case .low: String(localized: "Rischio basso", bundle: .module)
        case .medium: String(localized: "Rischio medio", bundle: .module)
        case .high: String(localized: "Rischio alto", bundle: .module)
        }
    }

    /// Il colore della pill nel catalogo asset dell'app, con varianti chiaro/scuro.
    public var colorName: String {
        switch self {
        case .low: "RiskLow"
        case .medium: "RiskMedium"
        case .high: "RiskHigh"
        }
    }
}
