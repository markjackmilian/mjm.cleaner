/// Aspetto dell'interfaccia: `auto` segue Impostazioni di Sistema.
public enum AppearancePreference: String, Sendable, CaseIterable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"
}

/// Legge l'aspetto senza mai far fallire il caricamento delle impostazioni: un file modificato a
/// mano o scritto da una versione diversa («Darkk», un numero, un oggetto) vale `auto` invece di
/// buttare via anche tutte le altre impostazioni. Si scrive il nome, così il file resta leggibile.
extension AppearancePreference: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let text = try? container.decode(String.self) else {
            self = .auto
            return
        }
        // Solo i nomi, senza distinzione fra maiuscole e minuscole: «1» non vale come numero.
        self = Self.allCases.first { PathText.equalsIgnoringCase($0.rawValue, text) } ?? .auto
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
