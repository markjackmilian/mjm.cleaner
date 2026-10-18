import CoreGraphics
import Foundation

// Stampa l'identificativo della finestra in primo piano del processo indicato (uno sheet aperto
// viene prima della sua finestra), attendendo che compaia per al massimo <secondi>.
// Uso: window-id <pid> <secondi>

let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = Int(arguments[1]), let seconds = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("uso: window-id <pid> <secondi>\n".utf8))
    exit(2)
}

let deadline = Date().addingTimeInterval(seconds)
while Date() < deadline {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let front = windows.first { window in
        window[kCGWindowOwnerPID as String] as? Int == pid && window[kCGWindowLayer as String] as? Int == 0
    }
    if let id = front?[kCGWindowNumber as String] as? Int {
        print(id)
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.2)
}
exit(1)
