using Avalonia;
using Avalonia.Headless;

[assembly: AvaloniaTestApplication(typeof(MjmCleaner.App.Tests.TestAppBuilder))]

namespace MjmCleaner.App.Tests;

public static class TestAppBuilder
{
    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UseHeadless(new AvaloniaHeadlessPlatformOptions());
}
