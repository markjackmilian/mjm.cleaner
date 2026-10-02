using Avalonia;
using Avalonia.Controls;

namespace MjmCleaner.App.Views;

/// <summary>Indicatore dei quattro passi del wizard: cerchio pieno sul passo corrente.</summary>
public partial class StepIndicator : UserControl
{
    public static readonly StyledProperty<int> CurrentStepProperty =
        AvaloniaProperty.Register<StepIndicator, int>(nameof(CurrentStep), 1);

    public StepIndicator() => InitializeComponent();

    public int CurrentStep
    {
        get => GetValue(CurrentStepProperty);
        set => SetValue(CurrentStepProperty, value);
    }

    protected override void OnPropertyChanged(AvaloniaPropertyChangedEventArgs change)
    {
        base.OnPropertyChanged(change);
        if (change.Property == CurrentStepProperty) UpdateSteps();
    }

    protected override void OnLoaded(Avalonia.Interactivity.RoutedEventArgs e)
    {
        base.OnLoaded(e);
        UpdateSteps();
    }

    private void UpdateSteps()
    {
        // La proprietà può cambiare prima che InitializeComponent abbia creato i figli con nome.
        Border?[] circles = [Step1, Step2, Step3, Step4];
        TextBlock?[] labels = [Label1, Label2, Label3, Label4];
        for (int i = 0; i < circles.Length; i++)
        {
            bool current = i + 1 == CurrentStep;
            circles[i]?.Classes.Set("current", current);
            labels[i]?.Classes.Set("current", current);
        }
    }
}
