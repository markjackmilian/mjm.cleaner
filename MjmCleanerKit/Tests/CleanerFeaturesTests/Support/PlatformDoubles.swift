import CleanerCore
import CleanerFeatures

/// `RecordingAppearance` dei test C#: registra ogni aspetto applicato.
@MainActor
final class FakeAppearance: AppearanceApplying {
    private(set) var applied: [AppearancePreference] = []

    func apply(_ preference: AppearancePreference) {
        applied.append(preference)
    }
}

/// `FixedPicker` dei test C#: restituisce sempre lo stesso percorso (o `nil`, come un annullamento).
/// Registra ogni richiesta: il titolo e se il pannello accetta i pacchetti.
@MainActor
final class FakePicker: FolderPicking {
    struct Request: Equatable {
        let title: String
        let allowsPackages: Bool
    }

    private let result: String?
    private(set) var requests: [Request] = []

    init(_ result: String? = nil) {
        self.result = result
    }

    func pickFolder(title: String, allowsPackages: Bool) async -> String? {
        requests.append(Request(title: title, allowsPackages: allowsPackages))
        return result
    }
}
