import AppKit
import CleanerFeatures
import SwiftUI

/// `FatalErrorWindow`: la composizione è fallita e l'app non può fare altro che dire cosa e dove.
struct StartupFailureView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(StartupFailure.title)
                .font(.title2.bold())
            Text(message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Esci") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
