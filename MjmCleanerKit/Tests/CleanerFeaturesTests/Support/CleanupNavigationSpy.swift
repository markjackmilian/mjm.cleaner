import CleanerCore
import CleanerFeatures

/// Le destinazioni del wizard: registra l'evento e conserva ciò che il passo ha consegnato.
@MainActor
final class CleanupNavigationSpy: NavigationSpy, CleanupNavigating {
    private(set) var scannedCategories: [CleanupCategory] = []
    private(set) var confirmedResults: [CategoryScanResult] = []
    private(set) var doneReport: CleanReport?
    private(set) var doneJournal: PendingJournal?

    func showScan(_ categories: [CleanupCategory]) {
        record("scan")
        scannedCategories = categories
    }

    func showConfirm(_ categories: [CleanupCategory], results: [CategoryScanResult]) {
        record("confirm")
        confirmedResults = results
    }

    func showDone(_ report: CleanReport, journal: PendingJournal?) {
        record("done")
        doneReport = report
        doneJournal = journal
    }

    func showSettings() {
        record("settings")
    }
}
