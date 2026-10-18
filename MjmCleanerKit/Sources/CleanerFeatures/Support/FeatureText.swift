import CleanerCore
import Darwin
import Foundation

/// Confronti di testo e messaggi d'errore dei modelli. `==` fra `String` confronta per equivalenza
/// canonica (NFC = NFD): per decidere si confrontano i byte UTF-8, come `StringComparison.Ordinal`
/// del C#. Stessa disciplina di `XcodeText` e `DockerText` del Core, che sono interni al Core.
enum FeatureText {
    /// `string.Equals(a, b, StringComparison.Ordinal)`.
    static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    /// Chiave per `Set`/`Dictionary` con la semantica di `StringComparer.Ordinal`.
    static func ordinalKey(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    /// `text.StartsWith(prefix, StringComparison.Ordinal)`.
    static func hasOrdinalPrefix(_ text: String, _ prefix: String) -> Bool {
        text.utf8.starts(with: prefix.utf8)
    }

    /// `Distinct()` con il comparatore predefinito (ordinale): resta la prima occorrenza, nell'ordine.
    static func distinct(_ texts: [String]) -> [String] {
        var seen = Set<[UInt8]>()
        return texts.filter { seen.insert(ordinalKey($0)).inserted }
    }

    /// Il testo di `ex.Message` mostrato nelle pagine. Gli errori del filesystem usano il testo di
    /// sistema dell'errno (spec §5.3), come `XcodeText.message` nel Core.
    static func message(_ error: any Error) -> String {
        switch error {
        case let error as FileSystemError:
            return error.message
        case let error as ProcessLaunchError:
            return String(cString: strerror(error.code))
        case is CancellationError:
            return String(localized: "operazione annullata", bundle: .module)
        case let error as any LocalizedError:
            return error.errorDescription ?? String(describing: error)
        default:
            return String(describing: error)
        }
    }
}
