using Avalonia.Headless.XUnit;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class ApplicationIdentityTests
{
    [AvaloniaFact]
    public void ApplicationUsesProductNameForPlatformMenus()
    {
        Assert.Equal("mjm.cleaner", App.Current?.Name);
        Assert.Equal("mjm.cleaner", new App().Name);
    }
}
