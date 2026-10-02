using System.Runtime.CompilerServices;
using MjmCleaner.App.ViewModels;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class SidebarSectionTests
{
    private static object Instance<T>() => RuntimeHelpers.GetUninitializedObject(typeof(T));

    [Fact]
    public void WizardPagesBelongToCleanup()
    {
        Assert.Equal(SidebarSection.Cleanup, SidebarSections.For(Instance<ChooseStepViewModel>()));
        Assert.Equal(SidebarSection.Cleanup, SidebarSections.For(Instance<ScanStepViewModel>()));
        Assert.Equal(SidebarSection.Cleanup, SidebarSections.For(Instance<ConfirmStepViewModel>()));
        Assert.Equal(SidebarSection.Cleanup, SidebarSections.For(Instance<DoneStepViewModel>()));
    }

    [Fact]
    public void ReportsBelongToTheirTool()
    {
        Assert.Equal(SidebarSection.Docker, SidebarSections.For(Instance<DockerViewModel>()));
        Assert.Equal(SidebarSection.Docker, SidebarSections.For(Instance<DockerReportViewModel>()));
        Assert.Equal(SidebarSection.Xcode, SidebarSections.For(Instance<XcodeViewModel>()));
        Assert.Equal(SidebarSection.Xcode, SidebarSections.For(Instance<XcodeReportViewModel>()));
        Assert.Equal(SidebarSection.History, SidebarSections.For(Instance<HistoryViewModel>()));
    }

    [Fact]
    public void IsWizardPageOnlyForTheFourSteps()
    {
        Assert.True(SidebarSections.IsWizardPage(Instance<ConfirmStepViewModel>()));
        Assert.False(SidebarSections.IsWizardPage(Instance<DockerViewModel>()));
        Assert.False(SidebarSections.IsWizardPage(null));
    }
}
