namespace MjmCleaner.App.ViewModels;

public enum SidebarSection
{
    Cleanup,
    Docker,
    Xcode,
    History,
}

/// <summary>La voce selezionata si ricava dalla pagina corrente: nessuno stato separato da tenere allineato.</summary>
public static class SidebarSections
{
    public static SidebarSection For(object? page) => page switch
    {
        DockerViewModel or DockerReportViewModel => SidebarSection.Docker,
        XcodeViewModel or XcodeReportViewModel => SidebarSection.Xcode,
        HistoryViewModel => SidebarSection.History,
        _ => SidebarSection.Cleanup,
    };

    public static bool IsWizardPage(object? page)
        => page is ChooseStepViewModel or ScanStepViewModel or ConfirmStepViewModel or DoneStepViewModel;
}
