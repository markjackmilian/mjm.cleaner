import CleanerFeatures
import SwiftUI

/// Provvisoria: la finestra principale, con sidebar e pagine, arriva con il Task 4.
struct MainView: View {
    let main: MainModel

    var body: some View {
        Text(verbatim: main.totalFreedAmount)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
