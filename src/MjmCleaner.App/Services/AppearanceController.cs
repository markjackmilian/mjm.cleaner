using Avalonia;
using Avalonia.Styling;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App.Services;

public interface IAppearanceController
{
    void Apply(AppearancePreference preference);
}

/// <summary>
/// L'aspetto vale per tutta l'applicazione, quindi per ogni finestra e foglio:
/// con <see cref="ThemeVariant.Default"/> Avalonia segue Impostazioni di Sistema in tempo reale.
/// </summary>
public sealed class AppearanceController(Application application) : IAppearanceController
{
    public void Apply(AppearancePreference preference) => application.RequestedThemeVariant = ThemeVariantFor(preference);

    public static ThemeVariant ThemeVariantFor(AppearancePreference preference) => preference switch
    {
        AppearancePreference.Light => ThemeVariant.Light,
        AppearancePreference.Dark => ThemeVariant.Dark,
        _ => ThemeVariant.Default,
    };
}
