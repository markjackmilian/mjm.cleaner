import CleanerCore
import Testing
@testable import CleanerFeatures

@MainActor
struct SettingsViewModelTests {
    private struct Fixture {
        let model: SettingsModel
        let store: FakeSettingsStore
        let appearance: FakeAppearance
        let events: Recorder<String>
    }

    private func create(_ settings: CleanerSettings = CleanerSettings(), picked: String? = nil) -> Fixture {
        let store = FakeSettingsStore(settings)
        let appearance = FakeAppearance()
        let events = Recorder<String>()
        let model = SettingsModel(
            store: store,
            appearance: appearance,
            folders: FakePicker(picked),
            onSaved: { events.append("saved") },
            onClose: { events.append("close") })
        return Fixture(model: model, store: store, appearance: appearance, events: events)
    }

    private func settings(_ change: (inout CleanerSettings) -> Void) -> CleanerSettings {
        var settings = CleanerSettings()
        change(&settings)
        return settings
    }

    @Test func pickingAnAppearancePreviewsItImmediately() {
        let fixture = create()
        fixture.model.appearance = .dark
        #expect(fixture.model.appearance == .dark)
        #expect(fixture.appearance.applied == [.dark])
        #expect(fixture.store.saves == 0)
    }

    @Test func cancelRestoresTheLoadedAppearanceAndCloses() {
        let fixture = create(settings { $0.appearance = .light })
        fixture.model.appearance = .dark
        fixture.model.cancel()
        #expect(fixture.appearance.applied.last == .light)
        #expect(fixture.events.values == ["close"])
        #expect(fixture.store.saves == 0)
    }

    @Test func closingFromTheTitleBarBehavesLikeCancel() {
        let fixture = create()
        fixture.model.appearance = .light
        fixture.model.dismiss()
        #expect(fixture.appearance.applied.last == .auto)
    }

    @Test func savePersistsAppearanceAndFoldersThenReturnsToStart() {
        let fixture = create(settings { $0.projectRoots = ["~/src"] })
        fixture.model.appearance = .dark
        fixture.model.save()
        fixture.model.dismiss()
        #expect(fixture.store.current.appearance == .dark)
        #expect(fixture.store.current.projectRoots == ["~/src"])
        #expect(fixture.events.values == ["saved", "close"])
        #expect(fixture.appearance.applied.last == .dark)
    }

    @Test func addingAFolderAppendsAndSelectsIt() async {
        let fixture = create(picked: "/Users/tester/projects")
        await fixture.model.addProjectRoot()
        #expect(fixture.model.projectRoots == ["/Users/tester/projects"])
        #expect(fixture.model.selectedProjectRoot == "/Users/tester/projects")
    }

    @Test func cancelledPickerAddsNothingAndDuplicatesAreNotRepeated() async {
        let fixture = create(settings { $0.largeFileRoots = ["/Volumes/Data"] }, picked: "/Volumes/Data")
        await fixture.model.addLargeFileRoot()
        #expect(fixture.model.largeFileRoots == ["/Volumes/Data"])

        let empty = create(picked: nil)
        await empty.model.addLargeFileRoot()
        #expect(empty.model.largeFileRoots.isEmpty)
    }

    @Test func removeIsDisabledWithoutSelection() {
        let fixture = create(settings { $0.projectRoots = ["/a", "/b"] })
        #expect(!fixture.model.canRemoveProjectRoot)
        fixture.model.selectedProjectRoot = "/a"
        #expect(fixture.model.canRemoveProjectRoot)
        fixture.model.removeProjectRoot()
        #expect(fixture.model.projectRoots == ["/b"])
        #expect(!fixture.model.canRemoveProjectRoot)
    }

    @Test func unchangedThresholdKeepsExactBytes() {
        let bytes: Int64 = 500 * 1024 * 1024 + 123
        let fixture = create(settings { $0.largeFileThresholdBytes = bytes })
        fixture.model.save()
        #expect(fixture.store.current.largeFileThresholdBytes == bytes)
    }

    // Solo Swift: in C# `Save` riportava i valori nei limiti con Math.Max; nessun test lo fissava.
    @Test func saveClampsTheNumbersLikeTheCSharpModel() {
        let fixture = create()
        fixture.model.largeFileThresholdMegabytes = 0
        fixture.model.downloadsMinAgeDays = -3
        fixture.model.logsMinAgeDays = -1
        fixture.model.nuGetMinAgeDays = 7
        fixture.model.save()
        #expect(fixture.store.current.largeFileThresholdBytes == 1024 * 1024)
        #expect(fixture.store.current.downloadsMinAgeDays == 0)
        #expect(fixture.store.current.logsMinAgeDays == 0)
        #expect(fixture.store.current.nuGetMinAgeDays == 7)
    }

    // Solo Swift: in C# un errore di scrittura chiudeva l'app; qui lo sheet resta aperto e lo dice.
    @Test func failedSaveKeepsTheSheetOpenAndExplainsWhy() {
        let fixture = create()
        fixture.store.failSaves(with: UnexpectedTestError(description: "disco pieno"))
        fixture.model.appearance = .dark

        fixture.model.save()

        #expect(fixture.events.values.isEmpty)
        #expect(fixture.model.saveErrorText == "Impostazioni non salvate: disco pieno")
        #expect(fixture.model.hasSaveError)
        // Non salvato: chiudere ripristina l'aspetto di prima.
        fixture.model.dismiss()
        #expect(fixture.appearance.applied.last == .auto)
    }

    // Solo Swift: un secondo valore uguale non riapplica l'aspetto (il setter C# notificava solo i cambi).
    @Test func reapplyingTheSameAppearanceDoesNothing() {
        let fixture = create()
        fixture.model.appearance = .auto
        #expect(fixture.appearance.applied.isEmpty)
    }

    // Solo Swift (review del Task 3): limiti che il piano dichiara e che i test portati non fissavano.
    @Test func saveClampsNegativeNuGetAgeAndHugeThresholds() {
        let fixture = create()
        fixture.model.nuGetMinAgeDays = -5
        fixture.model.largeFileThresholdMegabytes = Int.max
        fixture.model.save()
        #expect(fixture.store.current.nuGetMinAgeDays == 0)
        // I megabyte restano nell'intervallo di un `int` del C#: il prodotto non trabocca.
        #expect(fixture.store.current.largeFileThresholdBytes == Int64(Int32.max) * 1024 * 1024)
    }

    @Test func foldersAreComparedOrdinallyWhenAddingAndRemoving() async {
        let added = create(settings { $0.projectRoots = ["/x/Cafe\u{301}"] }, picked: "/x/Caf\u{E9}")
        await added.model.addProjectRoot()
        // NFC e NFD sono due percorsi diversi, come per `StringComparer.Ordinal`.
        #expect(added.model.projectRoots.map { Array($0.utf8) } == [Array("/x/Cafe\u{301}".utf8), Array("/x/Caf\u{E9}".utf8)])

        let removed = create(settings { $0.projectRoots = ["/x/Cafe\u{301}", "/x/Caf\u{E9}"] })
        removed.model.selectedProjectRoot = "/x/Caf\u{E9}"
        removed.model.removeProjectRoot()
        #expect(removed.model.projectRoots.map { Array($0.utf8) } == [Array("/x/Cafe\u{301}".utf8)])
    }

    /// Le Impostazioni non mostrano la selezione del passo 1: Salva la conserva, perché parte da
    /// `store.load()` e non da impostazioni nuove.
    @Test func saveKeepsTheRememberedCategorySelection() {
        let fixture = create(settings { $0.selectedCategoryIds = ["trash"] })

        fixture.model.save()

        #expect(fixture.store.current.selectedCategoryIds == ["trash"])
    }

    @Test func cancelledPickerKeepsTheCurrentSelection() async {
        let fixture = create(settings {
            $0.projectRoots = ["/a"]
            $0.largeFileRoots = ["/b"]
        }, picked: nil)
        fixture.model.selectedProjectRoot = "/a"
        fixture.model.selectedLargeFileRoot = "/b"

        await fixture.model.addProjectRoot()
        await fixture.model.addLargeFileRoot()

        #expect(fixture.model.selectedProjectRoot == "/a")
        #expect(fixture.model.selectedLargeFileRoot == "/b")
    }
}
