import Testing
@testable import CleanerFeatures

/// In C# la sezione si ricavava dal tipo del ViewModel (`SidebarSections.For(object)`); qui dal
/// tipo di pagina, senza costruire i modelli.
struct SidebarSectionTests {
    @Test func wizardPagesBelongToCleanup() {
        #expect([PageKind.choose, .scan, .confirm, .done].map(\.section) == [.cleanup, .cleanup, .cleanup, .cleanup])
    }

    @Test func reportsBelongToTheirTool() {
        #expect(PageKind.docker.section == .docker)
        #expect(PageKind.dockerReport.section == .docker)
        #expect(PageKind.xcode.section == .xcode)
        #expect(PageKind.xcodeReport.section == .xcode)
        #expect(PageKind.history.section == .history)
    }

    @Test func isWizardPageOnlyForTheFourSteps() {
        #expect(PageKind.allCases.filter(\.isWizardStep) == [.choose, .scan, .confirm, .done])
        #expect(!PageKind.docker.isWizardStep)
    }
}
