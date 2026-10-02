using Avalonia;
using Avalonia.Media;
using System;

namespace MjmCleaner.App;

class Program
{
    // Initialization code. Don't use any Avalonia, third-party APIs or any
    // SynchronizationContext-reliant code before AppMain is called: things aren't initialized
    // yet and stuff might break.
    [STAThread]
    public static void Main(string[] args) => BuildAvaloniaApp()
        .StartWithClassicDesktopLifetime(args);

    // Avalonia configuration, don't remove; also used by visual designer.
    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
#if DEBUG
            .WithDeveloperTools()
#endif
            .WithInterFont()
            // Su macOS Skia risolve ".AppleSystemUIFont" (San Francisco); "-apple-system" ricadrebbe su Inter.
            .With(new FontManagerOptions { DefaultFamilyName = OperatingSystem.IsMacOS() ? ".AppleSystemUIFont" : null })
            .LogToTrace();
}
