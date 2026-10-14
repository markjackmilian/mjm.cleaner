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
@MainActor
final class FakePicker: FolderPicking {
    private let result: String?
    private(set) var titles: [String] = []

    init(_ result: String? = nil) {
        self.result = result
    }

    func pickFolder(title: String) async -> String? {
        titles.append(title)
        return result
    }
}
