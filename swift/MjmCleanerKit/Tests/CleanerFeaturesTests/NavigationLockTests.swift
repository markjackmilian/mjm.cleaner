import CleanerCore
import Testing
@testable import CleanerFeatures

/// Il blocco della navigazione durante la cancellazione Xcode e il comportamento di «Pulizia» nella
/// sidebar (spec §6.3: il blocco è imposto dal modello, non solo dalla vista).
@MainActor
struct NavigationLockTests {
    private static func main(xcode: any XcodeCleanupServing = IdleXcode()) throws -> MainModel {
        MainModel(environment: try makeEnvironment(xcode: xcode), appearance: FakeAppearance(), folders: FakePicker())
    }

    private static func navigationIsOpen(_ main: MainModel) -> Bool {
        main.canNavigateGlobally && main.canShowSettings
    }

    @Test func sidebarCommandsAreDisabledWhileXcodeDeletesAndReenabledAfterwards() async throws {
        let service = XcodeViewModelTests.FakeXcode(XcodeViewModelTests.snapshot(XcodeViewModelTests.candidate("device", .device)))
        let main = try Self.main(xcode: service)
        main.showXcode()
        guard case .xcode(let xcode) = main.page else {
            Issue.record("La pagina Xcode non si è aperta")
            return
        }
        await xcode.initialLoad?.value
        #expect(Self.navigationIsOpen(main))

        try XcodeViewModelTests.onlyRow(xcode, .device).isSelected = true
        xcode.preview()
        let deleting = Task { await xcode.confirmDelete() }
        await service.executionStarted.wait()

        #expect(xcode.isDeleting)
        #expect(main.isXcodeBusy)
        #expect(!main.canNavigateGlobally)
        #expect(!main.canShowSettings)

        // Ogni richiesta di cambio pagina viene rifiutata: la pagina resta quella che elimina.
        for section in SidebarSection.allCases { main.select(section) }
        main.showSettings()
        #expect(main.page.kind == .xcode)
        #expect(main.section == .xcode)
        #expect(main.settings == nil)

        service.execution.open(XcodeViewModelTests.result())
        await deleting.value

        #expect(!main.isXcodeBusy)
        #expect(main.page.kind == .xcodeReport)
        #expect(Self.navigationIsOpen(main))
    }

    @Test func showCleanupLeavesAWizardPageUntouched() throws {
        let main = try Self.main()
        guard case .choose(let wizardPage) = main.page else {
            Issue.record("La finestra non parte dal passo 1")
            return
        }

        main.showCleanup()

        // Un ciclo in corso non viene interrotto: stessa istanza, non una nuova pagina del passo 1.
        guard case .choose(let current) = main.page else {
            Issue.record("La pagina è cambiata")
            return
        }
        #expect(current === wizardPage)
    }

    @Test func showCleanupFromHistoryReturnsToStepOne() throws {
        let main = try Self.main()
        main.showHistory()
        #expect(main.page.kind == .history)

        main.showCleanup()

        #expect(main.page.kind == .choose)
    }
}
