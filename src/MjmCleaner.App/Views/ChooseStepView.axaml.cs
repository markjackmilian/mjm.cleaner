using Avalonia.Controls;
using Avalonia.Markup.Xaml;

namespace MjmCleaner.App.Views;

public partial class ChooseStepView : UserControl
{
    public ChooseStepView() => InitializeComponent();

    private void InitializeComponent() => AvaloniaXamlLoader.Load(this);
}
