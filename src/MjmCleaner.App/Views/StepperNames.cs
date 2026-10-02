using Avalonia.Data.Converters;

namespace MjmCleaner.App.Views;

/// <summary>
/// Nomi accessibili dei pulsanti dello stepper compatto («Aumenta soglia file grandi»), derivati
/// dal nome del campo: il template di MacTheme li lega al <c>AutomationProperties.Name</c> del NumericUpDown.
/// </summary>
public static class StepperNames
{
    public static readonly FuncValueConverter<string?, string> Increase = new(name => Compose("Aumenta", name));
    public static readonly FuncValueConverter<string?, string> Decrease = new(name => Compose("Diminuisci", name));

    internal static string Compose(string verb, string? fieldName)
        => string.IsNullOrWhiteSpace(fieldName) ? verb : $"{verb} {char.ToLowerInvariant(fieldName[0])}{fieldName[1..]}";
}
