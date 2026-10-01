using Avalonia.Controls;
using Avalonia.Markup.Xaml;

namespace MjmCleaner.App.Views;

public partial class DockerView : UserControl
{
    public DockerView() => InitializeComponent();

    private void InitializeComponent() => AvaloniaXamlLoader.Load(this);
}
