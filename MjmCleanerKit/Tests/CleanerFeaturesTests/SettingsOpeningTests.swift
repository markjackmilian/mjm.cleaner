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
}
