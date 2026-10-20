import CleanerCore
import Testing
@testable import CleanerFeatures

/// Le prove di `SettingsOpeningTests.cs` sul collegamento fra comando e sheet. Il clic sul pulsante
/// della sidebar, ⌘, e la voce del menu dell'app sono della vista (piano 4b).
@MainActor
struct SettingsOpeningTests {
    private static func main() throws -> MainModel {
        MainModel(environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker())
    }

    @Test func showSettingsCommandOpensTheModalSettingsWindow() throws {
        let main = try Self.main()

        main.showSettings()

        #expect(main.settings != nil)
    }

    @Test func whileTheWindowIsOpenTheCommandIsDisabled() throws {
        let main = try Self.main()
        main.showSettings()
        let opened = try #require(main.settings)

        // Pulsante, ⌘, e voce di menu rispettano `canShowSettings`: finché lo sheet è aperto il comando è disabilitato.
        #expect(!main.canShowSettings)
        main.showSettings()
        #expect(main.settings === opened)

        opened.cancel()
        #expect(main.settings == nil)
        #expect(main.canShowSettings)
    }

    /// «Apri Impostazioni…» del passo 1 apre lo stesso sheet di ⌘, (spec
    /// `2026-10-20-package-exclusions-folder-warning-design.md`).
    @Test func stepOneOpensTheSettingsSheet() throws {
        let main = try Self.main()
        guard case .choose(let choose) = main.page else {
            Issue.record("La finestra non parte dal passo 1")
            return
        }

        choose.openSettings()

        #expect(main.settings != nil)
    }

    /// Dopo Salva il passo 1 si ricrea con le impostazioni nuove: la riga di una categoria che
    /// prima non aveva cartelle diventa disponibile e spuntata (spec
    /// `2026-10-20-package-exclusions-folder-warning-design.md`, «Dopo le Impostazioni» e
    /// «Primo avvio»).
    @Test func savingAProjectFolderFromStepOneMakesTheCategoryAvailable() async throws {
        let store = FakeSettingsStore(CleanerSettings())
        let main = MainModel(
            environment: try makeEnvironment(settings: store), appearance: FakeAppearance(), folders: FakePicker("/Users/tester/src"))
        guard case .choose(let before) = main.page else {
            Issue.record("La finestra non parte dal passo 1")
            return
        }
        let row = try #require(before.choices.first { $0.category.id == "project-build-output" })
        #expect(!row.isAvailable)
        #expect(before.selectedCountText == "3 categorie selezionate")

        before.openSettings()
        let settings = try #require(main.settings)
        await settings.addProjectRoot()
        settings.save()

        guard case .choose(let after) = main.page else {
            Issue.record("Dopo Salva la finestra non torna al passo 1")
            return
        }
        #expect(after !== before)
        let rowAfter = try #require(after.choices.first { $0.category.id == "project-build-output" })
        #expect(rowAfter.isAvailable)
        #expect(rowAfter.isSelected)
        #expect(after.selectedCountText == "4 categorie selezionate")
    }
}
