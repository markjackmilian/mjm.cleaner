import CleanerCore
import Testing
@testable import CleanerFeatures

/// Le prove di `ThemeTests.cs` che non dipendono da Avalonia: la mappatura dell'aspetto e il passo
/// segnato dall'indicatore. Token di colore, geometrie, ombre e anello di focus erano del tema
/// Avalonia (spec §9.2).
struct ThemeTests {
    @Test(arguments: [
        (AppearancePreference.auto, String?.none),
        (.light, "NSAppearanceNameAqua"),
        (.dark, "NSAppearanceNameDarkAqua"),
    ])
    func preferenceMapsToThemeVariant(preference: AppearancePreference, expected: String?) {
        #expect(preference.appKitAppearanceName == expected)
    }

    @Test func stepIndicatorMarksOnlyTheCurrentStep() {
        #expect([PageKind.choose, .scan, .confirm, .done].map(\.wizardStep) == [1, 2, 3, 4])
        #expect(PageKind.allCases.filter { !$0.isWizardStep }.allSatisfy { $0.wizardStep == nil })
    }
}
