import CleanerCore
import Foundation
import Observation

/// Ciò che il modello degli aggiornamenti chiede all'app (AppKit): chiudersi, mostrare un file nel
/// Finder, aprire la pagina della release nel browser.
@MainActor
public protocol UpdateHosting {
    func terminate()
    func reveal(_ path: String)
    func open(_ url: URL)
}

/// Gli aggiornamenti dalle release GitHub (spec 2026-10-19-app-updates-design.md): controllo
/// all'avvio e ogni 24 ore, download e verifica in background, proposta «Installa e riavvia».
/// Un controllo automatico che fallisce non mostra nulla e si ripete al giro dopo; uno manuale
/// mostra il motivo.
@MainActor
@Observable
public final class UpdateModel {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(Double)
        case ready(VerifiedUpdate)
        case installing
        case failed(String)
    }

    /// Il controllo automatico parte quando l'ultimo riuscito ha almeno 24 ore.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    @ObservationIgnored private let updater: any AppUpdating
    @ObservationIgnored private let settings: any SettingsStoring
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let host: any UpdateHosting
    /// Vero mentre una pulizia cancella: l'installazione chiuderebbe l'app a metà. Lo imposta `MainModel`.
    @ObservationIgnored public var isCleaning: @MainActor () -> Bool = { false }
    @ObservationIgnored private var started = false

    public private(set) var state = State.idle
    /// «Più tardi»: il banner resta nascosto fino al prossimo avvio.
    public private(set) var isBannerDismissed = false
    /// Un'installazione precedente non riuscita: l'app lo dice una volta, poi si azzera.
    public private(set) var installFailureText: String?

    public init(updater: any AppUpdating, settings: any SettingsStoring, clock: any WallClock, host: any UpdateHosting) {
        self.updater = updater
        self.settings = settings
        self.clock = clock
        self.host = host
    }

    public var currentVersionText: String { updater.currentVersion.description }

    public var lastCheckText: String? {
        settings.load().lastUpdateCheck.map { Formatting.historyDate($0) }
    }

    public var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    public var readyUpdate: VerifiedUpdate? {
        if case .ready(let update) = state { update } else { nil }
    }

    public var isBannerVisible: Bool { readyUpdate != nil && !isBannerDismissed }

    public var installMode: InstallMode { updater.installMode() }

    /// Il titolo del banner.
    public var bannerTitle: String {
        guard let update = readyUpdate else { return "" }
        return String(localized: "mjm.cleaner \(update.release.version.description) è pronto da installare.", bundle: .module)
    }

    /// Lo stato mostrato nelle Impostazioni, vuoto quando non c'è nulla da dire.
    public var statusText: String {
        switch state {
        case .idle, .installing:
            ""
        case .checking:
            String(localized: "Controllo in corso…", bundle: .module)
        case .downloading(let fraction):
            String(localized: "Download dell'aggiornamento: \(Int((fraction * 100).rounded()))%", bundle: .module)
        case .ready(let update):
            String(localized: "La versione \(update.release.version.description) è pronta da installare.", bundle: .module)
        case .upToDate:
            String(localized: "Hai già l'ultima versione.", bundle: .module)
        case .failed(let message):
            String(localized: "Aggiornamento non riuscito: \(message)", bundle: .module)
        }
    }

    public var hasFailed: Bool {
        if case .failed = state { true } else { false }
    }

    /// Il motivo per cui «Installa e riavvia» è disabilitato, o `nil`.
    public var installBlockedReason: String? {
        isCleaning() ? String(localized: "Attendi la fine della pulizia in corso.", bundle: .module) : nil
    }

    // MARK: Pianificazione

    /// All'avvio: l'esito dell'installazione precedente, poi un aggiornamento già scaricato, poi il
    /// controllo automatico se è dovuto. Le chiamate successive non fanno nulla.
    public func start() async {
        guard !started else { return }
        started = true
        if case .failed(let step) = updater.takeInstallOutcome() {
            installFailureText = String(
                localized: "Aggiornamento non riuscito (passo «\(step)»): è rimasta la versione \(currentVersionText). Il dettaglio è in install.log nella cartella updates dei dati dell'app.",
                bundle: .module)
        }
        if let cached = await updater.cachedUpdate() {
            state = .ready(cached)
            return
        }
        await checkIfDue()
    }

    /// Il controllo automatico, se attivo e dovuto: all'avvio e a ogni tick orario dell'app.
    public func checkIfDue() async {
        let saved = settings.load()
        guard saved.automaticUpdateChecks, !isBusy, readyUpdate == nil else { return }
        if let last = saved.lastUpdateCheck, clock.now.timeIntervalSince(last) < Self.checkInterval { return }
        await run(manual: false)
    }

    /// «Controlla ora»: ignora interruttore e soglia e mostra l'esito.
    public func checkNow() async {
        guard !isBusy else { return }
        if readyUpdate != nil {
            isBannerDismissed = false
            return
        }
        await run(manual: true)
    }

    private func run(manual: Bool) async {
        state = .checking
        do {
            let release = try await updater.check()
            var saved = settings.load()
            saved.lastUpdateCheck = clock.now
            try? settings.save(saved)
            guard let release else {
                state = manual ? .upToDate : .idle
                return
            }
            state = .downloading(0)
            let update = try await updater.prepare(release) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(fraction)
                }
            }
            isBannerDismissed = false
            state = .ready(update)
        } catch {
            state = manual ? .failed(FeatureText.message(error)) : .idle
        }
    }

    // MARK: Azioni del banner

    public func later() {
        isBannerDismissed = true
    }

    /// «Installa e riavvia»: avvia lo script e chiude l'app. Rifiutato mentre una pulizia cancella.
    public func install() {
        guard let update = readyUpdate, installBlockedReason == nil, installMode == .inPlace else { return }
        do {
            try updater.install(update)
        } catch {
            state = .failed(FeatureText.message(error))
            return
        }
        state = .installing
        host.terminate()
    }

    /// «Mostra nel Finder», quando il bundle non si può sostituire sul posto.
    public func revealUpdate() {
        guard let update = readyUpdate else { return }
        host.reveal(update.bundlePath)
    }

    /// «Novità»: la pagina della release su GitHub.
    public func openReleaseNotes() {
        guard let update = readyUpdate else { return }
        host.open(update.release.pageURL)
    }

    public func dismissInstallFailure() {
        installFailureText = nil
    }
}
