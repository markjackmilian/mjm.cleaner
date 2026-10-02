using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.ViewModels;
using MjmCleaner.App.Tests.Xcode;
using MjmCleaner.Core.Xcode;
using Xunit;

namespace MjmCleaner.App.Tests;

/// <summary>Il blocco della navigazione durante la cancellazione Xcode e il comportamento di «Pulizia» nella sidebar.</summary>
public sealed class NavigationLockTests
{
    private static IRelayCommand[] NavigationCommands(MainWindowViewModel vm)
        => [vm.ShowCleanupCommand, vm.ShowDockerCommand, vm.ShowXcodeCommand, vm.ShowHistoryCommand, vm.ShowSettingsCommand];

    [Fact]
    public async Task SidebarCommandsAreDisabledWhileXcodeDeletesAndReenabledAfterwards()
    {
        using TestHome home = await TestHome.CreateAsync();
        MainWindowViewModel main = new(home.Services);
        XcodeViewModelTests.FakeXcode service = new(XcodeViewModelTests.Snapshot(XcodeViewModelTests.Candidate("device", XcodeResourceKind.Device)))
        {
            Execution = new(TaskCreationOptions.RunContinuationsAsynchronously),
        };
        XcodeViewModel xcode = new(service, new XcodeViewModelTests.FakeHistory(), new XcodeViewModelTests.FakeLog(), main);
        main.GoTo(xcode);
        await xcode.InitialLoad;
        Assert.All(NavigationCommands(main), c => Assert.True(c.CanExecute(null)));

        xcode.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows.Single().IsSelected = true;
        xcode.PreviewCommand.Execute(null);
        Task deleting = xcode.ConfirmDeleteCommand.ExecuteAsync(null);

        Assert.True(xcode.IsDeleting);
        Assert.True(main.IsXcodeBusy);
        Assert.All(NavigationCommands(main), c => Assert.False(c.CanExecute(null)));

        service.Execution.SetResult(XcodeViewModelTests.Result());
        await deleting;

        Assert.False(main.IsXcodeBusy);
        Assert.All(NavigationCommands(main), c => Assert.True(c.CanExecute(null)));
    }

    [Fact]
    public async Task ShowCleanupLeavesAWizardPageUntouched()
    {
        using TestHome home = await TestHome.CreateAsync();
        MainWindowViewModel main = new(home.Services);
        object wizardPage = Assert.IsType<ChooseStepViewModel>(main.CurrentPage);

        main.ShowCleanupCommand.Execute(null);

        // Un ciclo in corso non viene interrotto: stessa istanza, non una nuova pagina del passo 1.
        Assert.Same(wizardPage, main.CurrentPage);
    }

    [Fact]
    public async Task ShowCleanupFromHistoryReturnsToStepOne()
    {
        using TestHome home = await TestHome.CreateAsync();
        MainWindowViewModel main = new(home.Services);
        main.ShowHistoryCommand.Execute(null);
        Assert.IsType<HistoryViewModel>(main.CurrentPage);

        main.ShowCleanupCommand.Execute(null);

        Assert.IsType<ChooseStepViewModel>(main.CurrentPage);
    }
}
