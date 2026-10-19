import Foundation

/// Perché un controllo, un download, una verifica o un'installazione non sono riusciti. Il testo è
/// quello che l'app mostra (Impostazioni, avviso dopo un'installazione fallita).
public enum UpdateError: Error, Equatable, Sendable, LocalizedError {
    /// GitHub ha risposto con uno stato diverso da 200 (403 per il limite di richieste, 404, …).
    case httpStatus(Int)
    /// La risposta non è il JSON di una release.
    case invalidResponse
    /// La release più recente non rispetta il formato delle release dell'app.
    case invalidRelease(String)
    /// Lo SHA-256 del file scaricato è diverso dal digest pubblicato.
    case digestMismatch
    /// Il bundle estratto non è una build di mjm.cleaner per la versione attesa.
    case invalidBundle(String)
    /// L'installazione non è partita.
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            String(localized: "GitHub ha risposto con lo stato HTTP \(status)", bundle: .module)
        case .invalidResponse:
            String(localized: "risposta di GitHub illeggibile", bundle: .module)
        case .invalidRelease(let reason):
            String(localized: "release non valida: \(reason)", bundle: .module)
        case .digestMismatch:
            String(localized: "il file scaricato non corrisponde al digest pubblicato", bundle: .module)
        case .invalidBundle(let reason):
            String(localized: "aggiornamento non valido: \(reason)", bundle: .module)
        case .installFailed(let reason):
            String(localized: "installazione non avviata: \(reason)", bundle: .module)
        }
    }
}
