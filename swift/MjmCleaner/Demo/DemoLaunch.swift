#if DEBUG
import AppKit
import CleanerCore
import CleanerFeatures
import Foundation

/// Avvio dimostrativo per gli screenshot (spec §9.4), solo in Debug: `-MJMDemo <pagina>` apre la
/// pagina con servizi finti e dati fissi, `-MJMAppearance light|dark` sceglie l'aspetto,
/// `-MJMWindowSize <L>x<A>` (interi positivi, per esempio `900x600`) porta la finestra principale a
/// quella misura in punti, barra degli strumenti compresa; una misura sotto il minimo dà il minimo
/// (900×652: i 900×600 della vista più i 52 della barra), un valore assente o malformato lascia la
/// misura che la finestra ricorda (`NSWindow Frame main` nei defaults). Nessun servizio finto tocca
/// il disco: un clic su «Elimina» restituisce un resoconto inventato.
struct DemoLaunch: Sendable {
    enum Page: String, CaseIterable, Sendable {
        case choose
        case scan
        case confirm
        case done
        case docker
        case dockerUnavailable = "docker-unavailable"
        case dockerReport = "docker-report"
        case xcode
        case xcodePreview = "xcode-preview"
        case xcodeReport = "xcode-report"
        case history
        case settings
        case startupFailure = "startup-failure"
    }

    let page: Page
    let appearance: AppearancePreference
    /// La misura del contenuto della finestra principale, in punti; `nil` lascia la predefinita.
    let windowSize: CGSize?

    static let current = parse(ProcessInfo.processInfo.arguments)

    /// `-MJMDemo` fra gli argomenti, con qualunque pagina: chi lancia vuole la demo, mai l'app vera.
    static let isRequested = ProcessInfo.processInfo.arguments.contains("-MJMDemo")

    /// Il testo della vista d'errore per una pagina che `Page` non conosce.
    static var unknownPageMessage: String {
        let page = value(after: "-MJMDemo", in: ProcessInfo.processInfo.arguments) ?? "nessuna"
        let known = Page.allCases.map(\.rawValue).joined(separator: ", ")
        return "Pagina demo sconosciuta: \(page). Pagine: \(known)."
    }

    static func parse(_ arguments: [String]) -> DemoLaunch? {
        guard let page = value(after: "-MJMDemo", in: arguments).flatMap(Page.init(rawValue:)) else { return nil }
        let appearance: AppearancePreference = switch value(after: "-MJMAppearance", in: arguments) {
        case "light": .light
        case "dark": .dark
        default: .auto
        }
        return DemoLaunch(
            page: page, appearance: appearance,
            windowSize: parseWindowSize(value(after: "-MJMWindowSize", in: arguments)))
    }

    /// `<L>x<A>` con due interi positivi fatti di sole cifre; qualunque altra forma non dà misura.
    static func parseWindowSize(_ text: String?) -> CGSize? {
        guard let parts = text?.split(separator: "x", omittingEmptySubsequences: false), parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isWholeNumber) }),
              let width = Int(parts[0]), let height = Int(parts[1]), width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// La finestra principale, quella di `Window(id: "main")` in `MjmCleanerApp`. Si riconosce dall'id
    /// della scena; se SwiftUI lo scrive in un'altra forma resta l'unica finestra con barra del titolo
    /// che può diventare principale e non è uno sheet. Con più candidati e nessun id riconosciuto non
    /// indovina: nessuna finestra, quindi la misura non cambia.
    @MainActor
    private static func mainWindow() -> NSWindow? {
        let candidates = NSApp.windows.filter { $0.styleMask.contains(.titled) && $0.canBecomeMain && $0.sheetParent == nil }
        let bySceneId = candidates.first {
            guard let id = $0.identifier?.rawValue else { return false }
            return id == "main" || id.hasPrefix("main-")
        }
        return bySceneId ?? (candidates.count == 1 ? candidates.first : nil)
    }

    /// Imposta la misura del contenuto, la stessa grandezza di `defaultSize` (1120×700): il contenuto
    /// arriva fino al bordo alto (`fullSizeContentView`), quindi la cattura esce della misura chiesta.
    /// Il minimo della vista (900×600) vale sotto la barra degli strumenti: la finestra non scende
    /// sotto 900×652 e una misura più piccola si ferma lì. Riprova per circa due secondi se la
    /// finestra non è ancora fra quelle dell'app, poi lo scrive nel log e lascia la misura com'è.
    @MainActor
    private static func resizeMainWindow(to size: CGSize) async {
        for _ in 0..<20 {
            if let window = mainWindow() {
                window.setContentSize(size)
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        NSLog("MJMWindowSize: finestra principale non trovata, misura invariata")
    }

    /// Apre la pagina chiesta passando dai metodi di `MainModel`, come farebbe l'utente.
    @MainActor
    func open(into startup: AppStartup) {
        // In primo piano, così gli screenshot mostrano la finestra attiva.
        NSApp.activate()
        if let windowSize {
            Task { await Self.resizeMainWindow(to: windowSize) }
        }
        guard page != .startupFailure else {
            let denied = FileSystemError(code: EACCES, path: DemoServices.paths.databaseFile)
            startup.fail(StartupFailure.message(paths: DemoServices.paths, error: denied))
            return
        }

        let environment: AppEnvironment
        do {
            environment = try DemoServices.environment(page: page, appearance: appearance)
        } catch {
            startup.fail(StartupFailure.message(paths: DemoServices.paths, error: error))
            return
        }
        let main = MainModel(environment: environment, appearance: AppKitAppearance(), folders: AppKitFolderPicker())
        startup.show(main)
        let categories = environment.categories().filter { DemoData.analyzedCategoryIds.contains($0.id) }

        switch page {
        case .choose, .startupFailure:
            break
        case .scan:
            main.showScan(categories)
        case .confirm:
            main.showConfirm(categories, results: DemoData.scanResults)
        case .done:
            main.showDone(DemoData.cleanReport, journal: nil)
        case .docker, .dockerUnavailable:
            main.select(.docker)
        case .dockerReport:
            main.showDockerReport(DemoData.dockerResult, diskBefore: DemoData.diskBefore, diskAfter: DemoData.diskAfter)
        case .xcode:
            main.select(.xcode)
        case .xcodePreview:
            main.select(.xcode)
            if case .xcode(let xcode) = main.page {
                Task {
                    await xcode.initialLoad?.value
                    for row in xcode.groups.flatMap(\.rows) where DemoData.previewedXcodeKeys.contains(row.candidate.key) {
                        row.isSelected = true
                    }
                    xcode.preview()
                }
            }
        case .xcodeReport:
            main.showXcodeReport(XcodeReportModel(
                history: environment.history, sessionLog: environment.sessionLog, navigation: main,
                result: DemoData.xcodeResult, journal: nil))
        case .history:
            main.select(.history)
        case .settings:
            main.showSettings()
        }
    }
}
#endif
