using Avalonia.Controls;
using MjmCleaner.App.Services;
using MjmCleaner.App.ViewModels;

namespace MjmCleaner.App.Views;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (DataContext is MainWindowViewModel vm)
        {
            // Il selettore cartelle appartiene alla finestra modale attiva, non a questa.
            vm.OpenSettingsWindow = async factory =>
            {
                SettingsWindow window = new();
                window.DataContext = factory(new StorageFolderPicker(window));
                await window.ShowDialog(this);
            };
        }
    }
}
