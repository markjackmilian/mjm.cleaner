using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using MjmCleaner.App.Services;
using MjmCleaner.App.ViewModels;
using MjmCleaner.App.Views;

namespace MjmCleaner.App;

public partial class App : Application
{
    public override void Initialize()
    {
        AvaloniaXamlLoader.Load(this);
    }

    public override async void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            AppServices services = await AppServices.CreateAsync();
            MainWindowViewModel viewModel = new(services);

            desktop.MainWindow = new MainWindow { DataContext = viewModel };
            await viewModel.RefreshTotalAsync();
        }

        base.OnFrameworkInitializationCompleted();
    }
}
