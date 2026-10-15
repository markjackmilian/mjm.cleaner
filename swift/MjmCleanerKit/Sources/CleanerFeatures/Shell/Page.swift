/// Le voci della sidebar (spec §6.2): Pulizia · Docker · Xcode · Storico.
public enum SidebarSection: Sendable, Hashable, CaseIterable {
    case cleanup
    case docker
    case xcode
    case history
}

/// Il tipo di pagina, senza il modello: la voce selezionata si ricava da qui, nessuno stato
/// separato da tenere allineato (`SidebarSections` del C#).
public enum PageKind: Sendable, Hashable, CaseIterable {
    case choose
    case scan
    case confirm
    case done
    case docker
    case dockerReport
    case xcode
    case xcodeReport
    case history

    public var section: SidebarSection {
        switch self {
        case .docker, .dockerReport: .docker
        case .xcode, .xcodeReport: .xcode
        case .history: .history
        case .choose, .scan, .confirm, .done: .cleanup
        }
    }

    /// I quattro passi del wizard di pulizia.
    public var isWizardStep: Bool {
        switch self {
        case .choose, .scan, .confirm, .done: true
        default: false
        }
    }

    /// Il passo (1–4) che lo `StepIndicator` segna come corrente; `nil` fuori dal wizard.
    public var wizardStep: Int? {
        switch self {
        case .choose: 1
        case .scan: 2
        case .confirm: 3
        case .done: 4
        default: nil
        }
    }
}

/// La pagina mostrata nella finestra principale, con il suo modello (spec §6.3).
@MainActor
public enum Page {
    case choose(ChooseStepModel)
    case scan(ScanStepModel)
    case confirm(ConfirmStepModel)
    case done(DoneStepModel)
    case docker(DockerModel)
    case dockerReport(DockerReportModel)
    case xcode(XcodeModel)
    case xcodeReport(XcodeReportModel)
    case history(HistoryModel)

    public var kind: PageKind {
        switch self {
        case .choose: .choose
        case .scan: .scan
        case .confirm: .confirm
        case .done: .done
        case .docker: .docker
        case .dockerReport: .dockerReport
        case .xcode: .xcode
        case .xcodeReport: .xcodeReport
        case .history: .history
        }
    }
}
