import CleanerCore

/// Nomi leggibili per gli identificativi salvati nello storico: il catalogo corrente, le
/// categorie di Docker e Xcode e gli ID di versioni precedenti del catalogo.
public struct CategoryNames: Sendable {
    private let names: [[UInt8]: String]

    private init(names: [[UInt8]: String]) {
        self.names = names
    }

    public static func build(_ catalog: [CleanupCategory]) -> CategoryNames {
        let fixed = [
            (DockerCategories.images, String(localized: "Immagini Docker", bundle: .module)),
            (DockerCategories.volumes, String(localized: "Volumi Docker", bundle: .module)),
            (DockerCategories.buildCache, String(localized: "Cache di build Docker", bundle: .module)),
            ("xcode-derived-data", String(localized: "DerivedData", bundle: .module)),
            ("xcode-device-support", String(localized: "Device Support", bundle: .module)),
            ("xcode-simulator-devices", String(localized: "Dispositivi simulati", bundle: .module)),
            ("xcode-runtimes", String(localized: "Runtime dei simulatori", bundle: .module)),
            ("trash-downloads-large", String(localized: "Cestino, Download e file grandi", bundle: .module)),
        ]

        var names: [[UInt8]: String] = [:]
        for (id, name) in fixed {
            names[FeatureText.ordinalKey(id)] = name
        }
        // Il catalogo corrente ha la precedenza, come l'assegnazione `names[category.Id]` del C#.
        for category in catalog {
            names[FeatureText.ordinalKey(category.id)] = category.displayName
        }
        return CategoryNames(names: names)
    }

    /// Il nome leggibile, o l'identificativo stesso se sconosciuto.
    public func name(for categoryId: String) -> String {
        names[FeatureText.ordinalKey(categoryId)] ?? categoryId
    }
}
