using Avalonia.Controls;
using Avalonia.Markup.Xaml;

namespace MjmCleaner.App.Views;

public partial class DockerReportView : UserControl
{
    public DockerReportView() => InitializeComponent();

    private void InitializeComponent() => AvaloniaXamlLoader.Load(this);
}
