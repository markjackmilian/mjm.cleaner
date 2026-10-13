/// Configurazione rifiutata da un inizializzatore: l'equivalente di `ArgumentException` nei
/// costruttori C#. Viene sempre lanciata prima che l'istanza esista: una configurazione
/// degenere non deve mai produrre un oggetto che la accetti.
public struct InvalidConfiguration: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
