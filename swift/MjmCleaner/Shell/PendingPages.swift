import CleanerFeatures
import SwiftUI

// Pagine provvisorie: i Task 5–10 sostituiscono ciascuna con la vista vera e la tolgono da qui;
// il Task 10 cancella il file.


struct XcodeView: View {
    let model: XcodeModel

    var body: some View {
        Text(verbatim: "Xcode")
    }
}

struct XcodeReportView: View {
    let model: XcodeReportModel

    var body: some View {
        Text(verbatim: "Resoconto Xcode")
    }
}

struct HistoryView: View {
    let model: HistoryModel

    var body: some View {
        Text(verbatim: "Storico")
    }
}

struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Text(verbatim: "Impostazioni")
    }
}
