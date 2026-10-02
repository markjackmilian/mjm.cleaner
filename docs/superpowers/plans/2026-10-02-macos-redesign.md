# Redesign macOS — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** portare la UI Avalonia di mjm.cleaner al redesign macOS (sidebar, toolbar/barra azioni, token chiaro/scuro, Impostazioni in finestra modale, preferenza Aspetto) senza cambiare flussi né logica.

**Architecture:** i token diventano `ThemeDictionaries` Light/Dark in `Styles/MacTheme.axaml`; l'aspetto si sceglie con `Application.RequestedThemeVariant`. `MainWindow` diventa sidebar + host di pagina; ogni view di pagina possiede la propria toolbar (52) e barra azioni (56) tramite classi di stile condivise. Le Impostazioni passano da pagina a `SettingsWindow` modale con un ViewModel testabile su interfacce.

**Tech Stack:** .NET 10, Avalonia 12.1.2 (FluentTheme), CommunityToolkit.Mvvm 8.4, xUnit v3, Avalonia.Headless.XUnit.

**Spec:** `docs/superpowers/specs/2026-10-02-macos-redesign-design.md` (riferimento visivo: canvas https://claude.ai/artifact/EDJZiBGXhMetgs7HjfyJCR, file `project/*.dc.html`).

## Global Constraints

- Nessun flusso, passo, comando o testo funzionale aggiunto o rimosso; i soli testi nuovi sono quelli elencati nella spec («Testi nuovi»).
- I comandi `Close`/`CloseCommand` dei ViewModel restano (logica invariata, coperti da test Xcode): si rimuovono solo i pulsanti «Chiudi» dalle view.
- Nessun colore letterale nelle view, salvo `White` su accento/distruttivo e i colori tile di `CategoryVisuals`.
- Accento `#0A66D8` in entrambi i temi. Font: famiglia di sistema `.AppleSystemUIFont` su macOS (spike: Skia risolve `.AppleSystemUIFont`; `-apple-system` e `SF Pro` no, ricadendo su Inter).
- Finestra principale 1120×700 iniziale, minima 900×600. Impostazioni modale, larga 700.
- Tutti i comandi shell richiedono `export PATH="/usr/local/share/dotnet:$PATH"`.
- Commit con trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## File

| File | Responsabilità |
|---|---|
| `src/MjmCleaner.Core/Settings/AppearancePreference.cs` (nuovo) | Enum `Auto/Light/Dark`. |
| `src/MjmCleaner.Core/Settings/CleanerSettings.cs` | Campo `Appearance`. |
| `src/MjmCleaner.App/Services/AppearanceController.cs` (nuovo) | `IAppearanceController` + mappatura su `ThemeVariant`. |
| `src/MjmCleaner.App/Services/FolderPicker.cs` (nuovo) | `IFolderPicker` + implementazione `StorageProvider`. |
| `src/MjmCleaner.App/Styles/MacTheme.axaml` | Token Light/Dark e stili condivisi. |
| `src/MjmCleaner.App/Styles/Icons.axaml` (nuovo) | `StreamGeometry` delle icone di sidebar/barre. |
| `src/MjmCleaner.App/ViewModels/CategoryVisuals.cs` (nuovo) | Colore tile e tracciato icona per ID categoria. |
| `src/MjmCleaner.App/ViewModels/CategoryNames.cs` (nuovo) | Nomi leggibili per lo Storico. |
| `src/MjmCleaner.App/ViewModels/SidebarSection.cs` (nuovo) | Enum + mappatura pagina → voce di sidebar. |
| `src/MjmCleaner.App/Views/StepIndicator.axaml(.cs)` (nuovo) | Indicatore passi 1–4. |
| `src/MjmCleaner.App/Views/SettingsWindow.axaml(.cs)` (nuovo, sostituisce `SettingsView`) | Finestra Impostazioni. |
| View e ViewModel esistenti | Solo presentazione, salvo le proprietà calcolate indicate. |

---

### Task 1: Preferenza Aspetto in Core

**Files:**
- Create: `src/MjmCleaner.Core/Settings/AppearancePreference.cs`
- Modify: `src/MjmCleaner.Core/Settings/CleanerSettings.cs`
- Test: `tests/MjmCleaner.Core.Tests/Settings/SettingsStoreTests.cs`

**Interfaces:**
- Produces: `enum AppearancePreference { Auto, Light, Dark }`; `CleanerSettings.Appearance` (init, default `Auto`), serializzato come stringa (`"Auto"|"Light"|"Dark"`).

- [ ] **Step 1: test che falliscono** — aggiungere a `SettingsStoreTests`:

```csharp
[Fact]
public void AppearanceDefaultsToAuto()
{
    Assert.Equal(AppearancePreference.Auto, new CleanerSettings().Appearance);
}

[Fact]
public void LegacyFileWithoutAppearanceLoadsAsAuto()
{
    MockFileSystem fs = new();
    AppPaths paths = new(Home);
    fs.AddFile(paths.SettingsFile, new MockFileData("""{ "DownloadsMinAgeDays": 12 }"""));

    CleanerSettings settings = new SettingsStore(fs, paths).Load();

    Assert.Equal(12, settings.DownloadsMinAgeDays);
    Assert.Equal(AppearancePreference.Auto, settings.Appearance);
}

[Fact]
public void AppearanceRoundTripsAsReadableString()
{
    MockFileSystem fs = new();
    AppPaths paths = new(Home);
    SettingsStore store = new(fs, paths);

    store.Save(new CleanerSettings { Appearance = AppearancePreference.Dark });

    Assert.Contains("\"Appearance\": \"Dark\"", fs.File.ReadAllText(paths.SettingsFile));
    Assert.Equal(AppearancePreference.Dark, store.Load().Appearance);
}
```

- [ ] **Step 2:** `dotnet test tests/MjmCleaner.Core.Tests --filter SettingsStoreTests` → FAIL (tipo `AppearancePreference` inesistente).
- [ ] **Step 3: implementazione**

```csharp
// AppearancePreference.cs
namespace MjmCleaner.Core.Settings;

/// <summary>Aspetto dell'interfaccia: <see cref="Auto"/> segue Impostazioni di Sistema.</summary>
public enum AppearancePreference
{
    Auto,
    Light,
    Dark,
}
```

In `CleanerSettings` (con `using System.Text.Json.Serialization;`):

```csharp
    /// <summary>Salvato come testo («Auto», «Light», «Dark») perché il file resti leggibile.</summary>
    [JsonConverter(typeof(JsonStringEnumConverter<AppearancePreference>))]
    public AppearancePreference Appearance { get; init; } = AppearancePreference.Auto;
```

- [ ] **Step 4:** stesso comando → PASS; poi `dotnet test` completo → PASS.
- [ ] **Step 5:** commit `feat(settings): add appearance preference`.

---

### Task 2: Token, font, icone e aspetto all'avvio

**Files:**
- Create: `src/MjmCleaner.App/Services/AppearanceController.cs`, `src/MjmCleaner.App/Styles/Icons.axaml`, `src/MjmCleaner.App/Views/StepIndicator.axaml(.cs)`
- Modify: `src/MjmCleaner.App/Styles/MacTheme.axaml`, `src/MjmCleaner.App/App.axaml`, `src/MjmCleaner.App/App.axaml.cs`, `src/MjmCleaner.App/Program.cs`
- Test: `tests/MjmCleaner.App.Tests/ThemeTests.cs` (nuovo)

**Interfaces:**
- Produces: `interface IAppearanceController { void Apply(AppearancePreference preference); }`; `sealed class AppearanceController(Application application) : IAppearanceController`; `static ThemeVariant AppearanceController.ThemeVariantFor(AppearancePreference)`.
- Produces (risorse): `WindowBrush`, `SidebarBrush`, `ContentBrush`, `GroupBrush`, `PrimaryTextBrush`, `SecondaryTextBrush`, `TertiaryTextBrush`, `SeparatorBrush`, `CardBorderBrush`, `ControlBorderBrush`, `HoverBrush`, `SelectedBrush`, `FieldBrush`, `StripeBrush`, `WellBrush`, `AccentBrush`, `AccentHoverBrush`, `AccentPressedBrush`, `DangerBrush`, `DestructiveBrush`, `DestructiveHoverBrush`, `WarningSurfaceBrush`, `WarningBorderBrush`, `WarningTextBrush`, `SuccessBrush`, `SuccessSurfaceBrush`, `RiskLow/Medium/HighTextBrush`, `RiskLow/Medium/HighSurfaceBrush`; `CanvasBrush`, `ToolbarBrush`, `CardBrush`, `BorderBrush`, `SubtleSurfaceBrush` restano come alias finché le view non migrano.
- Produces (classi): `TextBlock.PageTitle|PageSubtitle|ToolbarTitle|ToolbarSubtitle|RowTitle|RowDescription|Caption|SectionTitle|SidebarHeading|Eyebrow|Muted|FieldLabel`, `Border.Toolbar|ActionBar|SurfaceCard|Separator|RiskPill(.Low|.Medium|.High)|StatusPill|Tile|Banner`, `Button.Primary|Secondary|Destructive|SidebarItem(.selected)|Mini`, `Path.Icon`, `ItemsControl.Striped`.
- Produces (icone, `StreamGeometry`, viewBox 24): `IconSparkle`, `IconCube`, `IconHammer`, `IconClock`, `IconGear`, `IconShield`, `IconChevronRight`, `IconPlus`, `IconMinus`, `IconCheck`.
- Produces: `StepIndicator` con `public int CurrentStep` (StyledProperty, 1–4).

- [ ] **Step 1: test che falliscono** — `ThemeTests.cs`:

```csharp
using Avalonia;
using Avalonia.Headless.XUnit;
using Avalonia.Media;
using Avalonia.Styling;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Settings;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class ThemeTests
{
    [Theory]
    [InlineData(AppearancePreference.Auto, "Default")]
    [InlineData(AppearancePreference.Light, "Light")]
    [InlineData(AppearancePreference.Dark, "Dark")]
    public void PreferenceMapsToThemeVariant(AppearancePreference preference, string expected)
        => Assert.Equal(expected, AppearanceController.ThemeVariantFor(preference).Key.ToString());

    [AvaloniaTheory]
    [InlineData("Light", "#FFF7F7F9")]
    [InlineData("Dark", "#FF1E1E20")]
    public void ContentTokenFollowsVariant(string variant, string expected)
    {
        ThemeVariant theme = variant == "Dark" ? ThemeVariant.Dark : ThemeVariant.Light;
        Assert.True(Application.Current!.TryGetResource("ContentBrush", theme, out object? value));
        Assert.Equal(expected, ((ISolidColorBrush)value!).Color.ToString().ToUpperInvariant());
    }

    [AvaloniaFact]
    public void ApplySetsApplicationVariant()
    {
        AppearanceController controller = new(Application.Current!);
        controller.Apply(AppearancePreference.Dark);
        Assert.Equal(ThemeVariant.Dark, Application.Current!.RequestedThemeVariant);
        controller.Apply(AppearancePreference.Auto);
        Assert.Equal(ThemeVariant.Default, Application.Current!.RequestedThemeVariant);
    }
}
```

- [ ] **Step 2:** `dotnet test tests/MjmCleaner.App.Tests --filter ThemeTests` → FAIL (classe mancante).
- [ ] **Step 3: `AppearanceController.cs`**

```csharp
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
```

- [ ] **Step 4: `MacTheme.axaml`** — riscrivere `Styles.Resources` così (valori ARGB = rgba della spec; `StripeBrush` scuro è opaco `#313134` = `rgba(255,255,255,.03)` su `#2B2B2E`, perché le righe della tabella devono coprire lo sfondo a strisce):

```xml
<Styles.Resources>
  <ResourceDictionary>
    <ResourceDictionary.ThemeDictionaries>
      <ResourceDictionary x:Key="Light">
        <SolidColorBrush x:Key="WindowBrush" Color="#FFFFFF" />
        <SolidColorBrush x:Key="SidebarBrush" Color="#EEEDF1" />
        <SolidColorBrush x:Key="ContentBrush" Color="#F7F7F9" />
        <SolidColorBrush x:Key="GroupBrush" Color="#FFFFFF" />
        <SolidColorBrush x:Key="PrimaryTextBrush" Color="#1D1D1F" />
        <SolidColorBrush x:Key="SecondaryTextBrush" Color="#68686D" />
        <SolidColorBrush x:Key="TertiaryTextBrush" Color="#B4B4B8" />
        <SolidColorBrush x:Key="SeparatorBrush" Color="#17000000" />
        <SolidColorBrush x:Key="CardBorderBrush" Color="#14000000" />
        <SolidColorBrush x:Key="ControlBorderBrush" Color="#29000000" />
        <SolidColorBrush x:Key="CheckBorderBrush" Color="#42000000" />
        <SolidColorBrush x:Key="HoverBrush" Color="#07000000" />
        <SolidColorBrush x:Key="SelectedBrush" Color="#13000000" />
        <SolidColorBrush x:Key="FieldBrush" Color="#FFFFFF" />
        <SolidColorBrush x:Key="FieldHoverBrush" Color="#F2F2F4" />
        <SolidColorBrush x:Key="StripeBrush" Color="#F5F5F7" />
        <SolidColorBrush x:Key="WellBrush" Color="#0E000000" />
        <SolidColorBrush x:Key="DangerBrush" Color="#B42318" />
        <SolidColorBrush x:Key="WarningSurfaceBrush" Color="#FFF0DE" />
        <SolidColorBrush x:Key="WarningBorderBrush" Color="#2E9E4700" />
        <SolidColorBrush x:Key="WarningTextBrush" Color="#9E4700" />
        <SolidColorBrush x:Key="SuccessBrush" Color="#2E9D62" />
        <SolidColorBrush x:Key="SuccessSurfaceBrush" Color="#EAF8F0" />
        <SolidColorBrush x:Key="RiskLowTextBrush" Color="#55555A" />
        <SolidColorBrush x:Key="RiskLowSurfaceBrush" Color="#0E000000" />
        <SolidColorBrush x:Key="RiskMediumTextBrush" Color="#9E4700" />
        <SolidColorBrush x:Key="RiskMediumSurfaceBrush" Color="#FFF0DE" />
        <SolidColorBrush x:Key="RiskHighTextBrush" Color="#B42318" />
        <SolidColorBrush x:Key="RiskHighSurfaceBrush" Color="#FDECEA" />
      </ResourceDictionary>
      <ResourceDictionary x:Key="Dark">
        <SolidColorBrush x:Key="WindowBrush" Color="#232325" />
        <SolidColorBrush x:Key="SidebarBrush" Color="#2B2B2E" />
        <SolidColorBrush x:Key="ContentBrush" Color="#1E1E20" />
        <SolidColorBrush x:Key="GroupBrush" Color="#2B2B2E" />
        <SolidColorBrush x:Key="PrimaryTextBrush" Color="#F5F5F7" />
        <SolidColorBrush x:Key="SecondaryTextBrush" Color="#A1A1A6" />
        <SolidColorBrush x:Key="TertiaryTextBrush" Color="#5E5E62" />
        <SolidColorBrush x:Key="SeparatorBrush" Color="#17FFFFFF" />
        <SolidColorBrush x:Key="CardBorderBrush" Color="#14FFFFFF" />
        <SolidColorBrush x:Key="ControlBorderBrush" Color="#24FFFFFF" />
        <SolidColorBrush x:Key="CheckBorderBrush" Color="#3DFFFFFF" />
        <SolidColorBrush x:Key="HoverBrush" Color="#09FFFFFF" />
        <SolidColorBrush x:Key="SelectedBrush" Color="#1AFFFFFF" />
        <SolidColorBrush x:Key="FieldBrush" Color="#343437" />
        <SolidColorBrush x:Key="FieldHoverBrush" Color="#3C3C3F" />
        <SolidColorBrush x:Key="StripeBrush" Color="#313134" />
        <SolidColorBrush x:Key="WellBrush" Color="#14FFFFFF" />
        <SolidColorBrush x:Key="DangerBrush" Color="#FF8A80" />
        <SolidColorBrush x:Key="WarningSurfaceBrush" Color="#29FF9F0A" />
        <SolidColorBrush x:Key="WarningBorderBrush" Color="#40FF9F0A" />
        <SolidColorBrush x:Key="WarningTextBrush" Color="#FFB04D" />
        <SolidColorBrush x:Key="SuccessBrush" Color="#32D74B" />
        <SolidColorBrush x:Key="SuccessSurfaceBrush" Color="#2932D74B" />
        <SolidColorBrush x:Key="RiskLowTextBrush" Color="#C7C7CC" />
        <SolidColorBrush x:Key="RiskLowSurfaceBrush" Color="#14FFFFFF" />
        <SolidColorBrush x:Key="RiskMediumTextBrush" Color="#FFB04D" />
        <SolidColorBrush x:Key="RiskMediumSurfaceBrush" Color="#29FF9F0A" />
        <SolidColorBrush x:Key="RiskHighTextBrush" Color="#FF8A80" />
        <SolidColorBrush x:Key="RiskHighSurfaceBrush" Color="#2BFF453A" />
      </ResourceDictionary>
    </ResourceDictionary.ThemeDictionaries>
    <SolidColorBrush x:Key="AccentBrush" Color="#0A66D8" />
    <SolidColorBrush x:Key="AccentHoverBrush" Color="#1A72E0" />
    <SolidColorBrush x:Key="AccentPressedBrush" Color="#0957BA" />
    <SolidColorBrush x:Key="DestructiveBrush" Color="#D70015" />
    <SolidColorBrush x:Key="DestructiveHoverBrush" Color="#B00012" />
    <!-- Alias temporanei per le view non ancora migrate; rimossi nel Task 7. -->
    <StaticResource x:Key="CanvasBrush" ResourceKey="ContentBrush" />
    <StaticResource x:Key="ToolbarBrush" ResourceKey="WindowBrush" />
    <StaticResource x:Key="CardBrush" ResourceKey="GroupBrush" />
    <StaticResource x:Key="BorderBrush" ResourceKey="CardBorderBrush" />
    <StaticResource x:Key="SubtleSurfaceBrush" ResourceKey="WellBrush" />
  </ResourceDictionary>
</Styles.Resources>
```

  Se `StaticResource` verso una chiave di `ThemeDictionaries` non segue il cambio di tema (verificabile col test di Step 1 aggiungendo un caso `CardBrush`), duplicare invece le cinque chiavi alias dentro entrambi i dizionari di tema con gli stessi colori.

  Stili (sostituiscono quelli esistenti; i selettori `/template/ ContentPresenter#PART_ContentPresenter` servono perché FluentTheme imposta hover/pressed sul presenter del template, non sul `Button`):

```xml
<Style Selector="Window"><Setter Property="Background" Value="{DynamicResource ContentBrush}" /><Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}" /><Setter Property="FontSize" Value="13" /></Style>
<Style Selector="UserControl"><Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}" /></Style>

<Style Selector="TextBlock.PageTitle"><Setter Property="FontSize" Value="22" /><Setter Property="FontWeight" Value="Bold" /><Setter Property="LetterSpacing" Value="-0.33" /></Style>
<Style Selector="TextBlock.PageSubtitle"><Setter Property="FontSize" Value="13" /><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}" /><Setter Property="TextWrapping" Value="Wrap" /></Style>
<Style Selector="TextBlock.ToolbarTitle"><Setter Property="FontSize" Value="15" /><Setter Property="FontWeight" Value="Bold" /></Style>
<Style Selector="TextBlock.ToolbarSubtitle"><Setter Property="FontSize" Value="11" /><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}" /><Setter Property="TextTrimming" Value="CharacterEllipsis" /></Style>
<Style Selector="TextBlock.RowTitle"><Setter Property="FontSize" Value="13" /><Setter Property="FontWeight" Value="SemiBold" /></Style>
<Style Selector="TextBlock.RowDescription"><Setter Property="FontSize" Value="11.5" /><Setter Property="LineHeight" Value="15.5" /><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}" /><Setter Property="TextWrapping" Value="Wrap" /></Style>
<Style Selector="TextBlock.Caption"><Setter Property="FontSize" Value="11" /><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}" /></Style>
<Style Selector="TextBlock.SectionTitle"><Setter Property="FontSize" Value="13" /><Setter Property="FontWeight" Value="SemiBold" /><Setter Property="Margin" Value="4,0,0,2" /></Style>
<Style Selector="TextBlock.SidebarHeading"><Setter Property="FontSize" Value="11" /><Setter Property="FontWeight" Value="SemiBold" /><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}" /><Setter Property="Margin" Value="10,0,10,6" /></Style>
<Style Selector="TextBlock.Eyebrow"><Setter Property="FontSize" Value="11" /><Setter Property="FontWeight" Value="SemiBold" /><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}" /></Style>
<Style Selector="TextBlock.FieldLabel"><Setter Property="FontSize" Value="13" /></Style>
<Style Selector="TextBlock.Muted"><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}" /></Style>
<Style Selector="TextBlock.Numeric"><Setter Property="FontFeatures" Value="+tnum" /></Style>

<Style Selector="Border.Toolbar"><Setter Property="Height" Value="52" /><Setter Property="Background" Value="{DynamicResource WindowBrush}" /><Setter Property="BorderBrush" Value="{DynamicResource SeparatorBrush}" /><Setter Property="BorderThickness" Value="0,0,0,0.5" /><Setter Property="Padding" Value="24,0,20,0" /></Style>
<Style Selector="Border.ActionBar"><Setter Property="MinHeight" Value="56" /><Setter Property="Background" Value="{DynamicResource WindowBrush}" /><Setter Property="BorderBrush" Value="{DynamicResource SeparatorBrush}" /><Setter Property="BorderThickness" Value="0,0.5,0,0" /><Setter Property="Padding" Value="32,10,20,10" /></Style>
<Style Selector="Border.SurfaceCard"><Setter Property="Background" Value="{DynamicResource GroupBrush}" /><Setter Property="BorderBrush" Value="{DynamicResource CardBorderBrush}" /><Setter Property="BorderThickness" Value="0.5" /><Setter Property="CornerRadius" Value="10" /><Setter Property="BoxShadow" Value="0 1 2 0 #0A000000" /><Setter Property="ClipToBounds" Value="True" /></Style>
<Style Selector="Border.Separator"><Setter Property="Height" Value="0.5" /><Setter Property="Background" Value="{DynamicResource SeparatorBrush}" /></Style>
<Style Selector="Border.Banner"><Setter Property="Background" Value="{DynamicResource WarningSurfaceBrush}" /><Setter Property="BorderBrush" Value="{DynamicResource WarningBorderBrush}" /><Setter Property="BorderThickness" Value="0.5" /><Setter Property="CornerRadius" Value="10" /><Setter Property="Padding" Value="12" /></Style>
<Style Selector="Border.Banner TextBlock"><Setter Property="Foreground" Value="{DynamicResource WarningTextBrush}" /></Style>
<Style Selector="Border.RiskPill"><Setter Property="CornerRadius" Value="999" /><Setter Property="Padding" Value="8,2" /></Style>
<Style Selector="Border.RiskPill TextBlock"><Setter Property="FontSize" Value="11" /><Setter Property="FontWeight" Value="Medium" /></Style>
<Style Selector="Border.RiskPill.Low"><Setter Property="Background" Value="{DynamicResource RiskLowSurfaceBrush}" /></Style>
<Style Selector="Border.RiskPill.Low TextBlock"><Setter Property="Foreground" Value="{DynamicResource RiskLowTextBrush}" /></Style>
<Style Selector="Border.RiskPill.Medium"><Setter Property="Background" Value="{DynamicResource RiskMediumSurfaceBrush}" /></Style>
<Style Selector="Border.RiskPill.Medium TextBlock"><Setter Property="Foreground" Value="{DynamicResource RiskMediumTextBrush}" /></Style>
<Style Selector="Border.RiskPill.High"><Setter Property="Background" Value="{DynamicResource RiskHighSurfaceBrush}" /></Style>
<Style Selector="Border.RiskPill.High TextBlock"><Setter Property="Foreground" Value="{DynamicResource RiskHighTextBrush}" /></Style>
<Style Selector="Border.StatusPill"><Setter Property="Background" Value="{DynamicResource WellBrush}" /><Setter Property="CornerRadius" Value="999" /><Setter Property="Padding" Value="10,3" /></Style>
<Style Selector="Border.StatusPill TextBlock"><Setter Property="FontSize" Value="11" /><Setter Property="FontWeight" Value="Medium" /><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}" /></Style>
<Style Selector="Border.Tile"><Setter Property="Width" Value="28" /><Setter Property="Height" Value="28" /><Setter Property="CornerRadius" Value="7" /></Style>

<Style Selector="Path.Icon"><Setter Property="Width" Value="24" /><Setter Property="Height" Value="24" /><Setter Property="StrokeThickness" Value="1.8" /><Setter Property="StrokeLineCap" Value="Round" /><Setter Property="StrokeJoin" Value="Round" /><Setter Property="Stroke" Value="{DynamicResource AccentBrush}" /></Style>

<Style Selector="Button"><Setter Property="MinHeight" Value="28" /><Setter Property="MinWidth" Value="84" /><Setter Property="Padding" Value="14,5" /><Setter Property="CornerRadius" Value="6" /><Setter Property="FontSize" Value="13" /><Setter Property="HorizontalContentAlignment" Value="Center" /><Setter Property="VerticalContentAlignment" Value="Center" /><Setter Property="Background" Value="{DynamicResource FieldBrush}" /><Setter Property="BorderBrush" Value="{DynamicResource ControlBorderBrush}" /><Setter Property="BorderThickness" Value="0.5" /><Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}" /></Style>
<Style Selector="Button:pointerover /template/ ContentPresenter#PART_ContentPresenter"><Setter Property="Background" Value="{DynamicResource FieldHoverBrush}" /><Setter Property="BorderBrush" Value="{DynamicResource ControlBorderBrush}" /><Setter Property="Foreground" Value="{DynamicResource PrimaryTextBrush}" /></Style>
<Style Selector="Button:disabled /template/ ContentPresenter#PART_ContentPresenter"><Setter Property="Opacity" Value="0.4" /></Style>
<Style Selector="Button.Primary"><Setter Property="Background" Value="{DynamicResource AccentBrush}" /><Setter Property="BorderThickness" Value="0" /><Setter Property="Foreground" Value="White" /><Setter Property="FontWeight" Value="Medium" /></Style>
<Style Selector="Button.Primary:pointerover /template/ ContentPresenter#PART_ContentPresenter"><Setter Property="Background" Value="{DynamicResource AccentHoverBrush}" /><Setter Property="Foreground" Value="White" /></Style>
<Style Selector="Button.Primary:pressed /template/ ContentPresenter#PART_ContentPresenter"><Setter Property="Background" Value="{DynamicResource AccentPressedBrush}" /></Style>
<Style Selector="Button.Primary:disabled /template/ ContentPresenter#PART_ContentPresenter"><Setter Property="Background" Value="{DynamicResource AccentBrush}" /><Setter Property="Foreground" Value="White" /></Style>
<Style Selector="Button.Destructive"><Setter Property="Background" Value="{DynamicResource DestructiveBrush}" /><Setter Property="BorderThickness" Value="0" /><Setter Property="Foreground" Value="White" /><Setter Property="FontWeight" Value="SemiBold" /></Style>
<Style Selector="Button.Destructive:pointerover /template/ ContentPresenter#PART_ContentPresenter"><Setter Property="Background" Value="{DynamicResource DestructiveHoverBrush}" /><Setter Property="Foreground" Value="White" /></Style>
<Style Selector="Button.SidebarItem"><Setter Property="MinWidth" Value="0" /><Setter Property="Height" Value="30" /><Setter Property="Padding" Value="10,0" /><Setter Property="CornerRadius" Value="7" /><Setter Property="Background" Value="Transparent" /><Setter Property="BorderThickness" Value="0" /><Setter Property="HorizontalAlignment" Value="Stretch" /><Setter Property="HorizontalContentAlignment" Value="Stretch" /></Style>
<Style Selector="Button.SidebarItem:pointerover /template/ ContentPresenter#PART_ContentPresenter"><Setter Property="Background" Value="{DynamicResource HoverBrush}" /></Style>
<Style Selector="Button.SidebarItem.selected /template/ ContentPresenter#PART_ContentPresenter"><Setter Property="Background" Value="{DynamicResource SelectedBrush}" /></Style>
<Style Selector="Button.SidebarItem.selected TextBlock"><Setter Property="FontWeight" Value="Medium" /></Style>
<Style Selector="Button.Mini"><Setter Property="MinWidth" Value="28" /><Setter Property="MinHeight" Value="24" /><Setter Property="Width" Value="28" /><Setter Property="Height" Value="24" /><Setter Property="Padding" Value="0" /><Setter Property="CornerRadius" Value="0" /><Setter Property="Background" Value="Transparent" /><Setter Property="BorderThickness" Value="0" /></Style>
<Style Selector="Button:focus-visible /template/ ContentPresenter#PART_ContentPresenter"><Setter Property="BorderBrush" Value="{DynamicResource AccentBrush}" /><Setter Property="BorderThickness" Value="2" /></Style>

<Style Selector="CheckBox"><Setter Property="MinHeight" Value="0" /></Style>
<Style Selector="TextBox"><Setter Property="Background" Value="{DynamicResource FieldBrush}" /><Setter Property="BorderBrush" Value="{DynamicResource ControlBorderBrush}" /><Setter Property="BorderThickness" Value="0.5" /><Setter Property="CornerRadius" Value="5" /></Style>
<Style Selector="NumericUpDown"><Setter Property="Background" Value="{DynamicResource FieldBrush}" /><Setter Property="BorderBrush" Value="{DynamicResource ControlBorderBrush}" /><Setter Property="BorderThickness" Value="0.5" /><Setter Property="CornerRadius" Value="5" /><Setter Property="MinHeight" Value="24" /><Setter Property="Width" Value="110" /><Setter Property="FormatString" Value="0" /><Setter Property="HorizontalContentAlignment" Value="Right" /></Style>
<Style Selector="ProgressBar"><Setter Property="Background" Value="{DynamicResource WellBrush}" /><Setter Property="Foreground" Value="{DynamicResource AccentBrush}" /><Setter Property="CornerRadius" Value="3" /><Setter Property="MinHeight" Value="6" /></Style>
<Style Selector="Expander"><Setter Property="Background" Value="{DynamicResource GroupBrush}" /><Setter Property="BorderBrush" Value="{DynamicResource CardBorderBrush}" /><Setter Property="BorderThickness" Value="0.5" /><Setter Property="CornerRadius" Value="10" /><Setter Property="Padding" Value="12" /><Setter Property="HorizontalAlignment" Value="Stretch" /></Style>
<Style Selector="ListBox"><Setter Property="Background" Value="Transparent" /><Setter Property="BorderThickness" Value="0" /></Style>
<Style Selector="ScrollViewer"><Setter Property="HorizontalScrollBarVisibility" Value="Disabled" /></Style>
<Style Selector="ItemsControl.Striped > ContentPresenter"><Setter Property="Background" Value="{DynamicResource GroupBrush}" /></Style>
<Style Selector="ItemsControl.Striped > ContentPresenter:nth-child(2n)"><Setter Property="Background" Value="{DynamicResource StripeBrush}" /></Style>
```

  Aggiungere `<StyleInclude Source="avares://MjmCleaner.App/Styles/Icons.axaml" />` in `App.axaml`.

- [ ] **Step 5: `Icons.axaml`** (archi con flag separati da spazi: il parser Avalonia non accetta `012` compatto in modo affidabile):

```xml
<Styles xmlns="https://github.com/avaloniaui" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Styles.Resources>
    <StreamGeometry x:Key="IconSparkle">M12 3.5 L13.9 8.5 L18.9 10.4 L13.9 12.3 L12 17.3 L10.1 12.3 L5.1 10.4 L10.1 8.5 Z M19 16.5 V19.5 M17.5 18 H20.5</StreamGeometry>
    <StreamGeometry x:Key="IconCube">M12 3 L20 7.5 V16.5 L12 21 L4 16.5 V7.5 Z M4 7.5 L12 12 L20 7.5 M12 12 V21</StreamGeometry>
    <StreamGeometry x:Key="IconHammer">M13.5 4.5 L19.5 10.5 L17 13 L11 7 Z M12.5 8.5 L4.8 16.2 A1.9 1.9 0 0 0 7.5 18.9 L15.2 11.2</StreamGeometry>
    <StreamGeometry x:Key="IconClock">M3.5 12 A8.5 8.5 0 1 0 20.5 12 A8.5 8.5 0 1 0 3.5 12 Z M12 7.5 V12 L15 14</StreamGeometry>
    <StreamGeometry x:Key="IconGear">M9 12 A3 3 0 1 0 15 12 A3 3 0 1 0 9 12 Z M12 3 V5.5 M12 18.5 V21 M3 12 H5.5 M18.5 12 H21 M5.6 5.6 L7.4 7.4 M16.6 16.6 L18.4 18.4 M5.6 18.4 L7.4 16.6 M16.6 7.4 L18.4 5.6</StreamGeometry>
    <StreamGeometry x:Key="IconShield">M12 3.5 L19.5 6.5 V11.7 C19.5 16 16.4 19.4 12 20.5 C7.6 19.4 4.5 16 4.5 11.7 V6.5 Z M9 12 L11.2 14.2 L15.5 10</StreamGeometry>
    <StreamGeometry x:Key="IconChevronRight">M9 5 L16 12 L9 19</StreamGeometry>
    <StreamGeometry x:Key="IconPlus">M12 5 V19 M5 12 H19</StreamGeometry>
    <StreamGeometry x:Key="IconMinus">M5 12 H19</StreamGeometry>
    <StreamGeometry x:Key="IconCheck">M5 12.5 L10 17.5 L19 7.5</StreamGeometry>
  </Styles.Resources>
</Styles>
```

- [ ] **Step 6: `StepIndicator`** — `StepIndicator.axaml.cs`:

```csharp
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
        Border?[] circles = [Step1, Step2, Step3, Step4];
        for (int i = 0; i < circles.Length; i++)
        {
            circles[i]?.Classes.Set("current", i + 1 == CurrentStep);
        }
    }
}
```

`StepIndicator.axaml` — quattro `StackPanel` orizzontali (spacing 6) separati da `Border Width=18 Height=1 Background=SeparatorBrush`; ogni passo è `Border x:Name="StepN" Classes="StepCircle"` (18×18, r9, bordo 1 `CheckBorderBrush`) con `TextBlock` numero 11/SemiBold e un `TextBlock` etichetta 12 («Scegli», «Analizza», «Conferma», «Fatto»). Stili locali:

```xml
<UserControl.Styles>
  <Style Selector="Border.StepCircle"><Setter Property="Width" Value="18" /><Setter Property="Height" Value="18" /><Setter Property="CornerRadius" Value="9" /><Setter Property="BorderThickness" Value="1" /><Setter Property="BorderBrush" Value="{DynamicResource CheckBorderBrush}" /></Style>
  <Style Selector="Border.StepCircle TextBlock"><Setter Property="FontSize" Value="11" /><Setter Property="FontWeight" Value="SemiBold" /><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}" /><Setter Property="HorizontalAlignment" Value="Center" /><Setter Property="VerticalAlignment" Value="Center" /></Style>
  <Style Selector="Border.StepCircle.current"><Setter Property="Background" Value="{DynamicResource AccentBrush}" /><Setter Property="BorderThickness" Value="0" /></Style>
  <Style Selector="Border.StepCircle.current TextBlock"><Setter Property="Foreground" Value="White" /></Style>
  <Style Selector="TextBlock.StepLabel"><Setter Property="FontSize" Value="12" /><Setter Property="Foreground" Value="{DynamicResource SecondaryTextBrush}" /></Style>
</UserControl.Styles>
```

  L'etichetta del passo corrente diventa SemiBold e `PrimaryTextBrush`: in `UpdateSteps` impostare anche `Label1..Label4.Classes.Set("current", …)` con stile `TextBlock.StepLabel.current` (FontWeight SemiBold, Foreground PrimaryTextBrush). Contenitore: `StackPanel Orientation=Horizontal Spacing=8`, `AutomationProperties.Name="Avanzamento"`.

- [ ] **Step 7: avvio**
  - `App.axaml`: `RequestedThemeVariant="Default"`; `<FluentTheme>` con
    ```xml
    <FluentTheme.Palettes>
      <ColorPaletteResources x:Key="Light" Accent="#0A66D8" RegionColor="#F7F7F9" />
      <ColorPaletteResources x:Key="Dark" Accent="#0A66D8" RegionColor="#1E1E20" />
    </FluentTheme.Palettes>
    ```
  - `App.axaml.cs` `CreateMainWindowAsync`: dopo `AppServices.CreateAsync()` aggiungere `new AppearanceController(Current!).Apply(services.Settings.Load().Appearance);` prima di creare `MainWindow`.
  - `Program.cs`: dopo `.WithInterFont()` aggiungere `.With(new FontManagerOptions { DefaultFamilyName = OperatingSystem.IsMacOS() ? ".AppleSystemUIFont" : null })` (`using Avalonia.Media;`). Rimuovere i setter `FontFamily` da `MacTheme.axaml` (già fatto riscrivendo gli stili).

- [ ] **Step 8:** `dotnet test` → PASS (tutti, compresi `ThemeTests` e i test di layout esistenti). `dotnet run --project src/MjmCleaner.App`: l'app parte, testo in SF.
- [ ] **Step 9:** commit `feat(ui): add light and dark design tokens and appearance at startup`.

---

### Task 3: Finestra principale con sidebar e ⌘,

**Files:**
- Create: `src/MjmCleaner.App/ViewModels/SidebarSection.cs`
- Modify: `src/MjmCleaner.App/Views/MainWindow.axaml(.cs)`, `src/MjmCleaner.App/ViewModels/MainWindowViewModel.cs`, `src/MjmCleaner.App/App.axaml.cs`
- Test: `tests/MjmCleaner.App.Tests/SidebarSectionTests.cs` (nuovo), `tests/MjmCleaner.App.Tests/MainWindowLayoutTests.cs`

**Interfaces:**
- Produces: `enum SidebarSection { Cleanup, Docker, Xcode, History }`; `static SidebarSection SidebarSections.For(object? page)`.
- Produces su `MainWindowViewModel`: `SidebarSection CurrentSection`, `bool IsCleanupSelected|IsDockerSelected|IsXcodeSelected|IsHistorySelected`, `string TotalFreedAmount` (sostituisce `TotalFreedText`), `IRelayCommand ShowCleanupCommand`; `ShowSettingsCommand` resta (in questo task naviga ancora alla pagina; il Task 4 lo trasforma).
- Produces: `MainWindow` con host di pagina `ContentControl x:Name="PageHost"`.

- [ ] **Step 1: test che falliscono** — `SidebarSectionTests.cs` (costruzione dei ViewModel non serve: si usa `RuntimeHelpers.GetUninitializedObject` per avere istanze dei tipi senza servizi):

```csharp
using System.Runtime.CompilerServices;
using MjmCleaner.App.ViewModels;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class SidebarSectionTests
{
    private static object Instance<T>() => RuntimeHelpers.GetUninitializedObject(typeof(T));

    [Fact]
    public void WizardPagesBelongToCleanup()
    {
        Assert.Equal(SidebarSection.Cleanup, SidebarSections.For(Instance<ChooseStepViewModel>()));
        Assert.Equal(SidebarSection.Cleanup, SidebarSections.For(Instance<ScanStepViewModel>()));
        Assert.Equal(SidebarSection.Cleanup, SidebarSections.For(Instance<ConfirmStepViewModel>()));
        Assert.Equal(SidebarSection.Cleanup, SidebarSections.For(Instance<DoneStepViewModel>()));
    }

    [Fact]
    public void ReportsBelongToTheirTool()
    {
        Assert.Equal(SidebarSection.Docker, SidebarSections.For(Instance<DockerViewModel>()));
        Assert.Equal(SidebarSection.Docker, SidebarSections.For(Instance<DockerReportViewModel>()));
        Assert.Equal(SidebarSection.Xcode, SidebarSections.For(Instance<XcodeViewModel>()));
        Assert.Equal(SidebarSection.Xcode, SidebarSections.For(Instance<XcodeReportViewModel>()));
        Assert.Equal(SidebarSection.History, SidebarSections.For(Instance<HistoryViewModel>()));
    }

    [Fact]
    public void IsWizardPageOnlyForTheFourSteps()
    {
        Assert.True(SidebarSections.IsWizardPage(Instance<ConfirmStepViewModel>()));
        Assert.False(SidebarSections.IsWizardPage(Instance<DockerViewModel>()));
        Assert.False(SidebarSections.IsWizardPage(null));
    }
}
```

  Aggiornare `MainWindowLayoutTests`: cercare l'host con `window.FindControl<ContentControl>("PageHost")!` invece di `MaxWidth == 1120`, finestra `Width = 1120, Height = 700`, e l'assert di larghezza diventa `Assert.InRange(pageHost.Bounds.Width, 1, window.ClientSize.Width - 232);`. Aggiungere:

```csharp
[AvaloniaFact]
public void ShellHasSidebarAndNoCloseButtons()
{
    MainWindow window = new() { Width = 1120, Height = 700 };
    window.Show();
    window.UpdateLayout();

    string[] texts = [.. window.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text ?? "")];
    Assert.Contains("Pulizia", texts);
    Assert.Contains("Docker", texts);
    Assert.Contains("Xcode", texts);
    Assert.Contains("Storico", texts);
    Assert.Contains("Impostazioni…", texts);
    Assert.DoesNotContain(window.GetVisualDescendants().OfType<Button>(), b => b.Content as string == "Chiudi");
}
```

- [ ] **Step 2:** `dotnet test tests/MjmCleaner.App.Tests` → FAIL (tipi `SidebarSection*` mancanti, `PageHost` assente).
- [ ] **Step 3: `SidebarSection.cs`**

```csharp
namespace MjmCleaner.App.ViewModels;

public enum SidebarSection
{
    Cleanup,
    Docker,
    Xcode,
    History,
}

/// <summary>La voce selezionata si ricava dalla pagina corrente: nessuno stato separato da tenere allineato.</summary>
public static class SidebarSections
{
    public static SidebarSection For(object? page) => page switch
    {
        DockerViewModel or DockerReportViewModel => SidebarSection.Docker,
        XcodeViewModel or XcodeReportViewModel => SidebarSection.Xcode,
        HistoryViewModel => SidebarSection.History,
        _ => SidebarSection.Cleanup,
    };

    public static bool IsWizardPage(object? page)
        => page is ChooseStepViewModel or ScanStepViewModel or ConfirmStepViewModel or DoneStepViewModel;
}
```

- [ ] **Step 4: `MainWindowViewModel`** — modifiche:
  - `[ObservableProperty] private string _totalFreedAmount = "—";` al posto di `_totalFreedText`; `RefreshTotalAsync` imposta `TotalFreedAmount = FormatBytes(total);`.
  - Proprietà calcolate e notifiche in `OnCurrentPageChanged` (aggiungere anche `ShowCleanupCommand.NotifyCanExecuteChanged()` qui e in `OnXcodePageChanged`):
    ```csharp
    public SidebarSection CurrentSection => SidebarSections.For(CurrentPage);
    public bool IsCleanupSelected => CurrentSection == SidebarSection.Cleanup;
    public bool IsDockerSelected => CurrentSection == SidebarSection.Docker;
    public bool IsXcodeSelected => CurrentSection == SidebarSection.Xcode;
    public bool IsHistorySelected => CurrentSection == SidebarSection.History;
    ```
    con `[NotifyPropertyChangedFor(nameof(CurrentSection), nameof(IsCleanupSelected), nameof(IsDockerSelected), nameof(IsXcodeSelected), nameof(IsHistorySelected))]` sul campo `_currentPage`.
  - Nuovo comando (la voce «Pulizia» non interrompe un ciclo in corso; dalle altre sezioni riparte dal passo 1, come faceva «Chiudi»):
    ```csharp
    [RelayCommand(CanExecute = nameof(CanNavigateGlobally))]
    private void ShowCleanup()
    {
        if (!SidebarSections.IsWizardPage(CurrentPage)) StartOver();
    }
    ```
- [ ] **Step 5: `MainWindow.axaml`** — sostituire il contenuto:

```xml
<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:vm="clr-namespace:MjmCleaner.App.ViewModels"
        xmlns:chrome="using:Avalonia.Controls.Chrome"
        x:Class="MjmCleaner.App.Views.MainWindow"
        x:DataType="vm:MainWindowViewModel"
        Title="mjm.cleaner"
        Width="1120" Height="700" MinWidth="900" MinHeight="600"
        ExtendClientAreaToDecorationsHint="True"
        ExtendClientAreaTitleBarHeightHint="52">
    <Window.KeyBindings>
        <KeyBinding Gesture="Meta+OemComma" Command="{Binding ShowSettingsCommand}" />
    </Window.KeyBindings>
    <Grid ColumnDefinitions="232,*">
        <Border Grid.Column="0" Background="{DynamicResource SidebarBrush}"
                BorderBrush="{DynamicResource SeparatorBrush}" BorderThickness="0,0,0.5,0">
            <DockPanel Margin="10,0,10,12">
                <!-- Area dei semafori: trascinabile come una titlebar. -->
                <Border DockPanel.Dock="Top" Height="52" Background="Transparent"
                        chrome:WindowDecorationProperties.ElementRole="TitleBar" />
                <StackPanel DockPanel.Dock="Top" Spacing="2" AutomationProperties.Name="Sezioni">
                    <TextBlock Text="mjm.cleaner" Classes="SidebarHeading" />
                    <Button Classes="SidebarItem" Classes.selected="{Binding IsCleanupSelected}" Command="{Binding ShowCleanupCommand}">
                        <StackPanel Orientation="Horizontal" Spacing="8">
                            <Viewbox Width="16" Height="16"><Path Classes="Icon" Data="{StaticResource IconSparkle}" /></Viewbox>
                            <TextBlock Text="Pulizia" VerticalAlignment="Center" />
                        </StackPanel>
                    </Button>
                    <Button Classes="SidebarItem" Classes.selected="{Binding IsDockerSelected}" Command="{Binding ShowDockerCommand}">
                        <StackPanel Orientation="Horizontal" Spacing="8">
                            <Viewbox Width="16" Height="16"><Path Classes="Icon" Data="{StaticResource IconCube}" /></Viewbox>
                            <TextBlock Text="Docker" VerticalAlignment="Center" />
                        </StackPanel>
                    </Button>
                    <Button Classes="SidebarItem" Classes.selected="{Binding IsXcodeSelected}" Command="{Binding ShowXcodeCommand}">
                        <StackPanel Orientation="Horizontal" Spacing="8">
                            <Viewbox Width="16" Height="16"><Path Classes="Icon" Data="{StaticResource IconHammer}" /></Viewbox>
                            <TextBlock Text="Xcode" VerticalAlignment="Center" />
                        </StackPanel>
                    </Button>
                    <Button Classes="SidebarItem" Classes.selected="{Binding IsHistorySelected}" Command="{Binding ShowHistoryCommand}">
                        <StackPanel Orientation="Horizontal" Spacing="8">
                            <Viewbox Width="16" Height="16"><Path Classes="Icon" Data="{StaticResource IconClock}" /></Viewbox>
                            <TextBlock Text="Storico" VerticalAlignment="Center" />
                        </StackPanel>
                    </Button>
                </StackPanel>
                <Button DockPanel.Dock="Bottom" Classes="SidebarItem" Command="{Binding ShowSettingsCommand}">
                    <Grid ColumnDefinitions="Auto,*,Auto" ColumnSpacing="8">
                        <Viewbox Width="16" Height="16"><Path Classes="Icon" Data="{StaticResource IconGear}" Stroke="{DynamicResource SecondaryTextBrush}" /></Viewbox>
                        <TextBlock Grid.Column="1" Text="Impostazioni…" VerticalAlignment="Center" />
                        <TextBlock Grid.Column="2" Text="⌘," Classes="Caption" VerticalAlignment="Center" />
                    </Grid>
                </Button>
                <Border DockPanel.Dock="Bottom" Classes="SurfaceCard" Margin="4,0,4,10" Padding="12,12,12,11">
                    <StackPanel Spacing="2">
                        <TextBlock Text="Spazio liberato" Classes="Caption" />
                        <TextBlock Text="{Binding TotalFreedAmount}" Classes="Numeric" FontSize="20" FontWeight="Bold" LetterSpacing="-0.2" />
                        <TextBlock Text="liberati finora" Classes="Caption" />
                    </StackPanel>
                </Border>
                <Panel />
            </DockPanel>
        </Border>
        <ContentControl x:Name="PageHost" Grid.Column="1" Content="{Binding CurrentPage}" />
    </Grid>
</Window>
```

- [ ] **Step 6: menu ⌘,** — in `App.axaml.cs`, `OnFrameworkInitializationCompleted`, dentro il blocco `if (mainWindow is MainWindow { DataContext: MainWindowViewModel viewModel })` prima di `RefreshTotalAsync`:

```csharp
// Su macOS le voci del menu dell'applicazione finiscono nel menu «mjm.cleaner»,
// dove l'utente si aspetta Impostazioni… con ⌘,.
NativeMenu.SetMenu(this, new NativeMenu
{
    new NativeMenuItem("Impostazioni…")
    {
        Command = viewModel.ShowSettingsCommand,
        Gesture = new KeyGesture(Key.OemComma, KeyModifiers.Meta),
    },
});
```
  (`using Avalonia.Input;`)
- [ ] **Step 7: margine provvisorio** — finché le view non hanno toolbar e padding propri (Task 5–7), impostare `Margin="32,52,32,24"` su `PageHost` (52 in alto lascia libera l'area della titlebar). Il Task 5 lo rimuove.
- [ ] **Step 8:** `dotnet test` → PASS. `dotnet run --project src/MjmCleaner.App`: semafori sopra la sidebar, finestra trascinabile dall'area in alto, voci che navigano, ⌘, apre le Impostazioni (ancora come pagina).
- [ ] **Step 9:** commit `feat(ui): replace toolbar tabs with sidebar navigation`.

---

### Task 4: Impostazioni in finestra modale con Aspetto e liste cartelle

**Files:**
- Create: `src/MjmCleaner.App/Services/FolderPicker.cs`, `src/MjmCleaner.App/Views/SettingsWindow.axaml(.cs)`
- Delete: `src/MjmCleaner.App/Views/SettingsView.axaml(.cs)` e il relativo `DataTemplate` in `App.axaml`
- Modify: `src/MjmCleaner.App/ViewModels/SettingsViewModel.cs`, `src/MjmCleaner.App/ViewModels/MainWindowViewModel.cs`, `src/MjmCleaner.App/Views/MainWindow.axaml.cs`
- Test: `tests/MjmCleaner.App.Tests/SettingsViewModelTests.cs` (nuovo)

**Interfaces:**
- Consumes: `IAppearanceController`, `AppearancePreference`, `ISettingsStore`.
- Produces: `interface IFolderPicker { Task<string?> PickFolderAsync(string title); }`; `sealed class StorageFolderPicker(TopLevel topLevel) : IFolderPicker`.
- Produces: `SettingsViewModel(ISettingsStore store, IAppearanceController appearance, IFolderPicker folders, Action onSaved)`; proprietà `AppearancePreference Appearance`, `bool IsAuto|IsLight|IsDark`, `ObservableCollection<string> ProjectRoots|LargeFileRoots`, `string? SelectedProjectRoot|SelectedLargeFileRoot`, `int LargeFileThresholdMegabytes|DownloadsMinAgeDays|LogsMinAgeDays|NuGetMinAgeDays`; comandi `SaveCommand`, `CancelCommand`, `AddProjectRootCommand`, `RemoveProjectRootCommand`, `AddLargeFileRootCommand`, `RemoveLargeFileRootCommand`; `event EventHandler? CloseRequested`; `void Dismiss()` (ripristina l'aspetto se non salvato; idempotente).
- Produces su `MainWindowViewModel`: `Func<SettingsViewModel, Task>? OpenSettingsWindow { get; set; }`; `ShowSettingsCommand` diventa `IAsyncRelayCommand`.

- [ ] **Step 1: test che falliscono** — `SettingsViewModelTests.cs`:

```csharp
using MjmCleaner.App.Services;
using MjmCleaner.App.ViewModels;
using MjmCleaner.Core.Settings;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class SettingsViewModelTests
{
    private sealed class MemoryStore(CleanerSettings initial) : ISettingsStore
    {
        public CleanerSettings Current { get; private set; } = initial;
        public int Saves { get; private set; }
        public CleanerSettings Load() => Current;
        public void Save(CleanerSettings settings) { Current = settings; Saves++; }
    }

    private sealed class RecordingAppearance : IAppearanceController
    {
        public List<AppearancePreference> Applied { get; } = [];
        public void Apply(AppearancePreference preference) => Applied.Add(preference);
    }

    private sealed class FixedPicker(string? result) : IFolderPicker
    {
        public Task<string?> PickFolderAsync(string title) => Task.FromResult(result);
    }

    private static (SettingsViewModel Vm, MemoryStore Store, RecordingAppearance Appearance, List<string> Events) Create(
        CleanerSettings? settings = null, string? picked = null)
    {
        MemoryStore store = new(settings ?? new CleanerSettings());
        RecordingAppearance appearance = new();
        List<string> events = [];
        SettingsViewModel vm = new(store, appearance, new FixedPicker(picked), () => events.Add("saved"));
        vm.CloseRequested += (_, _) => events.Add("close");
        return (vm, store, appearance, events);
    }

    [Fact]
    public void PickingAnAppearancePreviewsItImmediately()
    {
        var (vm, store, appearance, _) = Create();
        vm.IsDark = true;
        Assert.Equal(AppearancePreference.Dark, vm.Appearance);
        Assert.Equal([AppearancePreference.Dark], appearance.Applied);
        Assert.Equal(0, store.Saves);
    }

    [Fact]
    public void CancelRestoresTheLoadedAppearanceAndCloses()
    {
        var (vm, store, appearance, events) = Create(new CleanerSettings { Appearance = AppearancePreference.Light });
        vm.IsDark = true;
        vm.CancelCommand.Execute(null);
        Assert.Equal(AppearancePreference.Light, appearance.Applied[^1]);
        Assert.Equal(["close"], events);
        Assert.Equal(0, store.Saves);
    }

    [Fact]
    public void ClosingFromTheTitleBarBehavesLikeCancel()
    {
        var (vm, _, appearance, _) = Create();
        vm.IsLight = true;
        vm.Dismiss();
        Assert.Equal(AppearancePreference.Auto, appearance.Applied[^1]);
    }

    [Fact]
    public void SavePersistsAppearanceAndFoldersThenReturnsToStart()
    {
        var (vm, store, appearance, events) = Create(new CleanerSettings { ProjectRoots = ["~/src"] });
        vm.IsDark = true;
        vm.SaveCommand.Execute(null);
        vm.Dismiss();
        Assert.Equal(AppearancePreference.Dark, store.Current.Appearance);
        Assert.Equal(["~/src"], store.Current.ProjectRoots);
        Assert.Equal(["saved", "close"], events);
        Assert.Equal(AppearancePreference.Dark, appearance.Applied[^1]);
    }

    [Fact]
    public async Task AddingAFolderAppendsAndSelectsIt()
    {
        var (vm, _, _, _) = Create(picked: "/Users/tester/projects");
        await vm.AddProjectRootCommand.ExecuteAsync(null);
        Assert.Equal(["/Users/tester/projects"], vm.ProjectRoots);
        Assert.Equal("/Users/tester/projects", vm.SelectedProjectRoot);
    }

    [Fact]
    public async Task CancelledPickerAddsNothingAndDuplicatesAreNotRepeated()
    {
        var (vm, _, _, _) = Create(new CleanerSettings { LargeFileRoots = ["/Volumes/Data"] }, picked: "/Volumes/Data");
        await vm.AddLargeFileRootCommand.ExecuteAsync(null);
        Assert.Equal(["/Volumes/Data"], vm.LargeFileRoots);

        var (empty, _, _, _) = Create(picked: null);
        await empty.AddLargeFileRootCommand.ExecuteAsync(null);
        Assert.Empty(empty.LargeFileRoots);
    }

    [Fact]
    public void RemoveIsDisabledWithoutSelection()
    {
        var (vm, _, _, _) = Create(new CleanerSettings { ProjectRoots = ["/a", "/b"] });
        Assert.False(vm.RemoveProjectRootCommand.CanExecute(null));
        vm.SelectedProjectRoot = "/a";
        Assert.True(vm.RemoveProjectRootCommand.CanExecute(null));
        vm.RemoveProjectRootCommand.Execute(null);
        Assert.Equal(["/b"], vm.ProjectRoots);
        Assert.False(vm.RemoveProjectRootCommand.CanExecute(null));
    }

    [Fact]
    public void UnchangedThresholdKeepsExactBytes()
    {
        long bytes = 500L * 1024 * 1024 + 123;
        var (vm, store, _, _) = Create(new CleanerSettings { LargeFileThresholdBytes = bytes });
        vm.SaveCommand.Execute(null);
        Assert.Equal(bytes, store.Current.LargeFileThresholdBytes);
    }
}
```

- [ ] **Step 2:** `dotnet test tests/MjmCleaner.App.Tests --filter SettingsViewModelTests` → FAIL (costruttore/`IFolderPicker` mancanti).
- [ ] **Step 3: `FolderPicker.cs`**

```csharp
using Avalonia.Controls;
using Avalonia.Platform.Storage;

namespace MjmCleaner.App.Services;

public interface IFolderPicker
{
    /// <summary>Percorso locale della cartella scelta, o <c>null</c> se l'utente annulla.</summary>
    Task<string?> PickFolderAsync(string title);
}

public sealed class StorageFolderPicker(TopLevel topLevel) : IFolderPicker
{
    public async Task<string?> PickFolderAsync(string title)
    {
        IReadOnlyList<IStorageFolder> folders = await topLevel.StorageProvider.OpenFolderPickerAsync(
            new FolderPickerOpenOptions { Title = title, AllowMultiple = false });
        return folders.Count == 0 ? null : folders[0].TryGetLocalPath();
    }
}
```

- [ ] **Step 4: `SettingsViewModel`** — riscrivere mantenendo la logica di salvataggio esistente:

```csharp
using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App.ViewModels;

public sealed partial class SettingsViewModel : ViewModelBase
{
    private readonly ISettingsStore _store;
    private readonly IAppearanceController _appearance;
    private readonly IFolderPicker _folders;
    private readonly Action _onSaved;
    private readonly AppearancePreference _loadedAppearance;
    private bool _saved;

    /// <summary>(commento esistente sui byte esatti della soglia: invariato)</summary>
    private readonly long _loadedThresholdBytes;
    private readonly int _loadedThresholdMegabytes;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsAuto), nameof(IsLight), nameof(IsDark))]
    private AppearancePreference _appearancePreference;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(RemoveProjectRootCommand))]
    private string? _selectedProjectRoot;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(RemoveLargeFileRootCommand))]
    private string? _selectedLargeFileRoot;

    [ObservableProperty] private int _largeFileThresholdMegabytes;
    [ObservableProperty] private int _downloadsMinAgeDays;
    [ObservableProperty] private int _logsMinAgeDays;
    [ObservableProperty] private int _nuGetMinAgeDays;

    public SettingsViewModel(ISettingsStore store, IAppearanceController appearance, IFolderPicker folders, Action onSaved)
    {
        _store = store;
        _appearance = appearance;
        _folders = folders;
        _onSaved = onSaved;

        CleanerSettings settings = store.Load();
        _loadedAppearance = settings.Appearance;
        _appearancePreference = settings.Appearance;
        ProjectRoots = [.. settings.ProjectRoots];
        LargeFileRoots = [.. settings.LargeFileRoots];
        _loadedThresholdBytes = settings.LargeFileThresholdBytes;
        _loadedThresholdMegabytes = (int)(settings.LargeFileThresholdBytes / (1024 * 1024));
        _largeFileThresholdMegabytes = _loadedThresholdMegabytes;
        _downloadsMinAgeDays = settings.DownloadsMinAgeDays;
        _logsMinAgeDays = settings.LogsMinAgeDays;
        _nuGetMinAgeDays = settings.NuGetMinAgeDays;
    }

    public event EventHandler? CloseRequested;

    public ObservableCollection<string> ProjectRoots { get; }
    public ObservableCollection<string> LargeFileRoots { get; }

    public AppearancePreference Appearance => AppearancePreference;

    public bool IsAuto { get => AppearancePreference == AppearancePreference.Auto; set { if (value) AppearancePreference = AppearancePreference.Auto; } }
    public bool IsLight { get => AppearancePreference == AppearancePreference.Light; set { if (value) AppearancePreference = AppearancePreference.Light; } }
    public bool IsDark { get => AppearancePreference == AppearancePreference.Dark; set { if (value) AppearancePreference = AppearancePreference.Dark; } }

    /// <summary>L'aspetto scelto si vede subito: diventa definitivo solo con Salva.</summary>
    partial void OnAppearancePreferenceChanged(AppearancePreference value) => _appearance.Apply(value);

    [RelayCommand]
    private void Save()
    {
        long thresholdBytes = LargeFileThresholdMegabytes == _loadedThresholdMegabytes
            ? _loadedThresholdBytes
            : Math.Max(1, LargeFileThresholdMegabytes) * 1024L * 1024L;

        CleanerSettings settings = _store.Load() with
        {
            Appearance = AppearancePreference,
            ProjectRoots = [.. ProjectRoots],
            LargeFileRoots = [.. LargeFileRoots],
            LargeFileThresholdBytes = thresholdBytes,
            DownloadsMinAgeDays = Math.Max(0, DownloadsMinAgeDays),
            LogsMinAgeDays = Math.Max(0, LogsMinAgeDays),
            NuGetMinAgeDays = Math.Max(0, NuGetMinAgeDays),
        };

        _store.Save(settings);
        _saved = true;
        _onSaved();
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    [RelayCommand]
    private void Cancel()
    {
        Dismiss();
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>Chiusura senza salvare (Annulla o pulsante rosso): torna l'aspetto di prima.</summary>
    public void Dismiss()
    {
        if (!_saved) _appearance.Apply(_loadedAppearance);
    }

    [RelayCommand]
    private async Task AddProjectRootAsync() => SelectedProjectRoot = await AddFolderAsync(ProjectRoots, "Scegli una cartella di progetto") ?? SelectedProjectRoot;

    [RelayCommand(CanExecute = nameof(CanRemoveProjectRoot))]
    private void RemoveProjectRoot() { if (SelectedProjectRoot is { } root) ProjectRoots.Remove(root); SelectedProjectRoot = null; }

    private bool CanRemoveProjectRoot() => SelectedProjectRoot is not null;

    [RelayCommand]
    private async Task AddLargeFileRootAsync() => SelectedLargeFileRoot = await AddFolderAsync(LargeFileRoots, "Scegli una cartella in cui cercare file grandi") ?? SelectedLargeFileRoot;

    [RelayCommand(CanExecute = nameof(CanRemoveLargeFileRoot))]
    private void RemoveLargeFileRoot() { if (SelectedLargeFileRoot is { } root) LargeFileRoots.Remove(root); SelectedLargeFileRoot = null; }

    private bool CanRemoveLargeFileRoot() => SelectedLargeFileRoot is not null;

    private async Task<string?> AddFolderAsync(ObservableCollection<string> target, string title)
    {
        string? path = await _folders.PickFolderAsync(title);
        if (path is null) return null;
        if (!target.Contains(path, StringComparer.Ordinal)) target.Add(path);
        return path;
    }
}
```

  Nota: il nome del campo è `_appearancePreference` (proprietà generata `AppearancePreference`) per non collidere col tipo enum; `Appearance` è l'alias di sola lettura usato dai test.
- [ ] **Step 5:** `dotnet test --filter SettingsViewModelTests` → PASS.
- [ ] **Step 6: `MainWindowViewModel`**

```csharp
/// <summary>Assegnato dalla finestra: il ViewModel non crea finestre.</summary>
public Func<SettingsViewModel, Task>? OpenSettingsWindow { get; set; }

[RelayCommand(CanExecute = nameof(CanNavigateGlobally))]
private async Task ShowSettingsAsync()
{
    if (OpenSettingsWindow is null) return;
    SettingsViewModel settings = new(_services.Settings, new AppearanceController(Avalonia.Application.Current!), FolderPicker, StartOver);
    await OpenSettingsWindow(settings);
}

/// <summary>Assegnato dalla finestra insieme a <see cref="OpenSettingsWindow"/>.</summary>
public IFolderPicker FolderPicker { get; set; } = null!;
```

  (`AsyncRelayCommand` non consente esecuzioni concorrenti: un secondo ⌘, con la finestra aperta non ne apre un'altra.)
- [ ] **Step 7: `MainWindow.axaml.cs`**

```csharp
protected override void OnDataContextChanged(EventArgs e)
{
    base.OnDataContextChanged(e);
    if (DataContext is MainWindowViewModel vm)
    {
        vm.FolderPicker = new StorageFolderPicker(this);
        vm.OpenSettingsWindow = settings => new SettingsWindow { DataContext = settings }.ShowDialog(this);
    }
}
```

- [ ] **Step 8: `SettingsWindow`** — code-behind:

```csharp
public partial class SettingsWindow : Window
{
    public SettingsWindow() => InitializeComponent();

    protected override void OnDataContextChanged(EventArgs e)
    {
        base.OnDataContextChanged(e);
        if (DataContext is SettingsViewModel vm) vm.CloseRequested += (_, _) => Close();
    }

    protected override void OnClosed(EventArgs e)
    {
        (DataContext as SettingsViewModel)?.Dismiss();
        base.OnClosed(e);
    }
}
```

  `SettingsWindow.axaml` — `Window` `Title="Impostazioni" Width="700" Height="820" CanResize="False" CanMinimize="False" CanMaximize="False" WindowStartupLocation="CenterOwner" ExtendClientAreaToDecorationsHint="True" ExtendClientAreaTitleBarHeightHint="52"`, `x:DataType="vm:SettingsViewModel"`. `DockPanel`:
  1. Top: `Border Classes="Toolbar" Padding="16,0" chrome:WindowDecorationProperties.ElementRole="TitleBar"` con `TextBlock Text="Impostazioni" FontSize="13" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center"`.
  2. Bottom: `Border Classes="ActionBar" Background="{DynamicResource ContentBrush}" Padding="20,0"` con `StackPanel Orientation=Horizontal HorizontalAlignment=Right Spacing=10`: `Button Content="Annulla" Command="{Binding CancelCommand}" IsCancel="True"`, `Button Classes="Primary" Content="Salva" Command="{Binding SaveCommand}" IsDefault="True"`.
  3. Fill: `ScrollViewer` → `StackPanel Margin="28,20,28,8" Spacing="22"`:
     - `TextBlock Text="Personalizza i percorsi e le soglie usate durante l'analisi." FontSize="12" Classes="Muted"`.
     - **Aspetto**: `StackPanel Spacing=6` → `TextBlock Classes=SectionTitle Text="Aspetto"`; `Border Classes=SurfaceCard Padding="16,14,16,12"` → `StackPanel Orientation=Horizontal Spacing=20` con tre `RadioButton GroupName="Appearance" Classes="AppearanceOption"` legati a `IsAuto`/`IsLight`/`IsDark`; contenuto di ciascuno: `StackPanel Spacing=6` con l'anteprima 88×56 r7 (vedi sotto) e `TextBlock` 12 («Automatico», «Chiaro», «Scuro»); poi `TextBlock Classes=Caption FontSize=11.5 Margin="4,0" Text="Automatico segue l'aspetto scelto in Impostazioni di Sistema."`.
       Anteprime (colori fissi, sono illustrazioni dei temi): Chiaro = `Border Width=88 Height=56 CornerRadius=7 Background=#FFFFFF ClipToBounds` con `DockPanel` → barra sinistra `Border Width=26 Background=#E4E4E8` e `StackPanel Margin="7,8" Spacing=4` di tre barre alte 4 r2 (`AccentBrush` larga 60%, poi `#D8D8DC` ×2). Scuro = stesso con `#232325`, `#3A3A3D`, `#4A4A4E`. Automatico = metà sinistra chiara (barra `#E4E4E8` larga 22) e metà destra `#2B2B2E`, ognuna con due barre (accento + `#D8D8DC`/`#4A4A4E`).
       Stili locali: `RadioButton.AppearanceOption` → `Template` con solo `ContentPresenter` (niente pallino), `Cursor=Hand`; `RadioButton.AppearanceOption Border.Preview` → `BoxShadow="0 0 0 0.5 #73808080"`; `RadioButton.AppearanceOption:checked Border.Preview` → `BoxShadow="0 0 0 2 #0A66D8"`; `RadioButton.AppearanceOption:checked TextBlock.OptionLabel` → `FontWeight=SemiBold`; `RadioButton.AppearanceOption:focus-visible Border.Preview` → `BoxShadow="0 0 0 3 #800A66D8"`. Ogni `RadioButton` ha `AutomationProperties.Name` uguale all'etichetta.
     - **Progetti .NET**: titolo; `Border Classes=SurfaceCard Padding=12` → lista cartelle; didascalia «Cartelle di progetto in cui cercare bin e obj.».
     - **File grandi**: titolo; `Border Classes=SurfaceCard` → `StackPanel`: `StackPanel Margin=12 Spacing=8` (`TextBlock "Cartelle in cui cercare"` + lista cartelle), `Border Classes=Separator Margin="12,0"`, riga soglia `Grid ColumnDefinitions="*,Auto,38" Margin="12,10"`: `TextBlock "Soglia file grandi"`, `NumericUpDown Value="{Binding LargeFileThresholdMegabytes}" Minimum=1 Maximum=100000 AutomationProperties.Name="Soglia file grandi"`, `TextBlock "MB" Classes=Muted Margin="8,0,0,0"`; didascalia «Vengono proposti solo i file più grandi della soglia.».
     - **Età minima**: titolo; `Border Classes=SurfaceCard` → tre righe come la soglia separate da `Border.Separator Margin="12,0"`: «Download» / `DownloadsMinAgeDays`, «Log» / `LogsMinAgeDays`, «Pacchetti NuGet» / `NuGetMinAgeDays`, unità «giorni», `Minimum=0 Maximum=3650`; didascalia esistente «L'età dei pacchetti NuGet si basa sull'ultimo accesso registrato dal filesystem: è un'euristica, non una certezza.» e, sopra, quella esistente «I file più recenti restano esclusi dall'analisi.».
     - **Lista cartelle** (usata due volte, con binding diversi): `Border CornerRadius=7 Background=FieldBrush BorderBrush=ControlBorderBrush BorderThickness=0.5 ClipToBounds` → `DockPanel`: Bottom `Border Height=24 Background=WellBrush BorderBrush=SeparatorBrush BorderThickness="0,0.5,0,0"` con `StackPanel Orientation=Horizontal`: `Button Classes=Mini Command=AddXCommand AutomationProperties.Name="Aggiungi cartella"` (icona `IconPlus` 11px, `Stroke=PrimaryTextBrush`, `StrokeThickness=2.6`), `Border Width=0.5 Background=SeparatorBrush`, `Button Classes=Mini Command=RemoveXCommand AutomationProperties.Name="Rimuovi cartella selezionata"` (`IconMinus`), `Border Width=0.5`; Fill `Panel Height=84`: `TextBlock "Nessuna cartella. Premi + per aggiungerne una." FontSize=12 Classes=Muted Center IsVisible="{Binding !X.Count}"` e `ListBox ItemsSource=X SelectedItem=SelectedX IsVisible="{Binding !!X.Count}"` con item `TextBlock` 13 `TextTrimming=CharacterEllipsis`.
- [ ] **Step 9:** rimuovere `SettingsView.axaml(.cs)` e il suo `DataTemplate`. `dotnet build` → nessun errore; `dotnet test` → PASS.
- [ ] **Step 10:** prova manuale: ⌘, apre la finestra modale centrata; Scuro cambia subito tutta l'app; Annulla e pulsante rosso ripristinano; Salva persiste, chiude e mostra il passo 1; + apre il pannello cartelle; − disabilitato senza selezione.
- [ ] **Step 11:** commit `feat(ui): move settings to a modal window with appearance picker`.

---

### Task 5: Pulizia — passi Scegli, Analizza, Conferma, Fatto

**Files:**
- Create: `src/MjmCleaner.App/ViewModels/CategoryVisuals.cs`
- Modify: `src/MjmCleaner.App/ViewModels/ChooseStepViewModel.cs`, `src/MjmCleaner.App/Views/ChooseStepView.axaml`, `ScanStepView.axaml`, `ConfirmStepView.axaml`, `DoneStepView.axaml`, `MainWindow.axaml` (azzerare il margine provvisorio di `PageHost`)
- Test: `tests/MjmCleaner.App.Tests/ChooseStepTests.cs` (nuovo), `tests/MjmCleaner.App.Tests/MainWindowLayoutTests.cs`

**Interfaces:**
- Produces: `sealed record CategoryVisual(string TileColor, string IconData)`; `static CategoryVisual CategoryVisuals.For(string categoryId)`.
- Produces su `CategoryChoice`: `bool IsChild`, `bool ShowSeparator` (init, `false` per la prima riga), `Thickness SeparatorMargin` (`72` o `116` a sinistra), `Thickness RowPadding` (`16,11` o `60,11,16,11`), `IBrush TileBrush`, `Geometry Icon`, `bool IsLowRisk|IsMediumRisk|IsHighRisk`, `RiskLabel` con iniziale maiuscola. `Indent` viene rimosso.
- Produces su `ChooseStepViewModel`: `int SelectedCount`, `string SelectedCountText`; `AnalyzeCommand.CanExecute` falso con 0 selezioni.

- [ ] **Step 1: test che falliscono** — `ChooseStepTests.cs`:

```csharp
using MjmCleaner.App.ViewModels;
using MjmCleaner.Core.Categories;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class ChooseStepTests
{
    private static CleanupCategory Category(string id, string? parent = null, RiskLevel risk = RiskLevel.Low)
        => new(id, id, "descrizione", risk, false, parent, []);

    [Theory]
    [InlineData(0, "Nessuna categoria selezionata")]
    [InlineData(1, "1 categoria selezionata")]
    [InlineData(3, "3 categorie selezionate")]
    public void CountTextAgrees(int count, string expected)
        => Assert.Equal(expected, ChooseStepViewModel.CountText(count));

    [Fact]
    public void ChildRowsAreIndentedWithDeeperSeparator()
    {
        CategoryChoice child = new(Category("nuget-packages", parent: "dev-caches"), false) { ShowSeparator = true };
        CategoryChoice root = new(Category("logs"), false) { ShowSeparator = true };
        Assert.True(child.IsChild);
        Assert.Equal(116, child.SeparatorMargin.Left);
        Assert.Equal(60, child.RowPadding.Left);
        Assert.Equal(72, root.SeparatorMargin.Left);
        Assert.Equal(16, root.RowPadding.Left);
    }

    [Theory]
    [InlineData(RiskLevel.Low, "Rischio basso")]
    [InlineData(RiskLevel.Medium, "Rischio medio")]
    [InlineData(RiskLevel.High, "Rischio alto")]
    public void RiskPillTextNamesTheLevel(RiskLevel risk, string expected)
        => Assert.Equal(expected, new CategoryChoice(Category("logs", risk: risk), false).RiskLabel);

    [Theory]
    [InlineData("system-caches", "#66788F")]
    [InlineData("dev-caches", "#7457E8")]
    [InlineData("nuget-packages", "#3567D0")]
    [InlineData("project-build-output", "#1D8784")]
    [InlineData("logs", "#85858B")]
    [InlineData("trash", "#D2453A")]
    [InlineData("downloads-large", "#E8833A")]
    public void TilesUseTheDesignColors(string id, string color)
        => Assert.Equal(color, CategoryVisuals.For(id).TileColor);
}
```

  Verificare la firma reale del costruttore `CleanupCategory` in `src/MjmCleaner.Core/Categories/CleanupCategory.cs` e adattare `Category(...)` se l'ordine dei parametri differisce.
- [ ] **Step 2:** `dotnet test --filter ChooseStepTests` → FAIL.
- [ ] **Step 3: `CategoryVisuals.cs`** (tracciati tradotti dal canvas, viewBox 24):

```csharp
namespace MjmCleaner.App.ViewModels;

public sealed record CategoryVisual(string TileColor, string IconData);

/// <summary>Tile colorata e glifo per categoria, come nel redesign; ID sconosciuti ricevono la tile neutra.</summary>
public static class CategoryVisuals
{
    private const string Drive = "M5.5 7 H18.5 A2.5 2.5 0 0 1 21 9.5 V14.5 A2.5 2.5 0 0 1 18.5 17 H5.5 A2.5 2.5 0 0 1 3 14.5 V9.5 A2.5 2.5 0 0 1 5.5 7 Z M7 12 H12 M15.9 12 A0.6 0.6 0 1 0 17.1 12 A0.6 0.6 0 1 0 15.9 12 Z";
    private const string Code = "M8 8 L4 12 L8 16 M16 8 L20 12 L16 16 M13.5 6 L10.5 18";
    private const string Cube = "M12 3 L20 7.5 V16.5 L12 21 L4 16.5 V7.5 Z M4 7.5 L12 12 L20 7.5 M12 12 V21";
    private const string Folder = "M3.5 7.5 A2 2 0 0 1 5.5 5.5 H9.3 L11.3 7.5 H18.5 A2 2 0 0 1 20.5 9.5 V16.5 A2 2 0 0 1 18.5 18.5 H5.5 A2 2 0 0 1 3.5 16.5 Z";
    private const string Document = "M7 3.5 H14 L18 7.5 V20.5 H7 Z M14 3.5 V7.5 H18 M10 12 H15 M10 15.5 H15";
    private const string Trash = "M4.5 7 H19.5 M10 7 V4.5 H14 V7 M6.5 7 L7.5 20 H16.5 L17.5 7 M10.5 11 V16 M13.5 11 V16";
    private const string Download = "M12 4 V15 M7.5 10.5 L12 15 L16.5 10.5 M5 19.5 H19";

    public static CategoryVisual For(string categoryId) => categoryId switch
    {
        "system-caches" => new("#66788F", Drive),
        "dev-caches" => new("#7457E8", Code),
        "nuget-packages" => new("#3567D0", Cube),
        "project-build-output" => new("#1D8784", Folder),
        "logs" => new("#85858B", Document),
        "trash" => new("#D2453A", Trash),
        "downloads-large" => new("#E8833A", Download),
        _ => new("#85858B", Document),
    };
}
```

- [ ] **Step 4: `CategoryChoice` e `ChooseStepViewModel`**

```csharp
public sealed partial class CategoryChoice(CleanupCategory category, bool isSelected) : ObservableObject
{
    [ObservableProperty]
    private bool _isSelected = isSelected;

    public CleanupCategory Category { get; } = category;

    public string DisplayName => Category.DisplayName;
    public string Description => Category.Description;

    public string RiskLabel => Category.Risk switch
    {
        RiskLevel.Low => "Rischio basso",
        RiskLevel.Medium => "Rischio medio",
        RiskLevel.High => "Rischio alto",
        _ => string.Empty,
    };

    public bool IsLowRisk => Category.Risk == RiskLevel.Low;
    public bool IsMediumRisk => Category.Risk == RiskLevel.Medium;
    public bool IsHighRisk => Category.Risk == RiskLevel.High;

    /// <summary>I pacchetti NuGet compaiono rientrati sotto le cache di sviluppo.</summary>
    public bool IsChild => Category.ParentId is not null;

    /// <summary>La prima riga del gruppo non ha separatore sopra.</summary>
    public bool ShowSeparator { get; init; }

    /// <summary>Separatore allineato al titolo della riga: più rientrato sopra una riga figlia.</summary>
    public Thickness SeparatorMargin => new(IsChild ? 116 : 72, 0, 0, 0);
    public Thickness RowPadding => IsChild ? new Thickness(60, 11, 16, 11) : new Thickness(16, 11);

    public IBrush TileBrush => new SolidColorBrush(Color.Parse(CategoryVisuals.For(Category.Id).TileColor));
    public Geometry Icon => StreamGeometry.Parse(CategoryVisuals.For(Category.Id).IconData);
}
```

  (`using Avalonia.Media;`). In `ChooseStepViewModel`:

```csharp
Choices = [.. services.BuildCategories().Select((category, index) =>
    new CategoryChoice(category, remembered.Contains(category.Id)) { ShowSeparator = index > 0 })];
foreach (CategoryChoice choice in Choices)
{
    choice.PropertyChanged += (_, e) =>
    {
        if (e.PropertyName != nameof(CategoryChoice.IsSelected)) return;
        OnPropertyChanged(nameof(SelectedCount));
        OnPropertyChanged(nameof(SelectedCountText));
        AnalyzeCommand.NotifyCanExecuteChanged();
    };
}
```

```csharp
public int SelectedCount => Choices.Count(c => c.IsSelected);
public string SelectedCountText => CountText(SelectedCount);

public static string CountText(int count) => count switch
{
    0 => "Nessuna categoria selezionata",
    1 => "1 categoria selezionata",
    _ => $"{count} categorie selezionate",
};

private bool CanAnalyze() => SelectedCount > 0;
```

  e `[RelayCommand(CanExecute = nameof(CanAnalyze))]` su `Analyze` (il controllo `selected.Length == 0` resta).
- [ ] **Step 5:** `dotnet test --filter ChooseStepTests` → PASS.
- [ ] **Step 6: struttura comune delle pagine wizard** — ogni view è:

```xml
<DockPanel LastChildFill="True">
    <Border DockPanel.Dock="Top" Classes="Toolbar" chrome:WindowDecorationProperties.ElementRole="TitleBar">
        <Grid ColumnDefinitions="*,Auto">
            <StackPanel VerticalAlignment="Center" Spacing="1">
                <TextBlock Text="Pulizia" Classes="ToolbarTitle" />
                <TextBlock Text="Passo N di 4" Classes="ToolbarSubtitle" />
            </StackPanel>
            <views:StepIndicator Grid.Column="1" CurrentStep="N" VerticalAlignment="Center" />
        </Grid>
    </Border>
    <Border DockPanel.Dock="Bottom" Classes="ActionBar"> … </Border>
    <ScrollViewer> <StackPanel Margin="32,24,32,20" Spacing="16"> … </StackPanel> </ScrollViewer>
</DockPanel>
```

  (`xmlns:views="clr-namespace:MjmCleaner.App.Views"`, `xmlns:chrome="using:Avalonia.Controls.Chrome"`). Rimuovere le righe «1 · Scegli — …» (sostituite dall'indicatore). In `MainWindow.axaml` togliere `Margin` da `PageHost`.
- [ ] **Step 7: `ChooseStepView`** — contenuto: titolo `PageTitle` «Cosa vuoi pulire?» + `PageSubtitle` invariato; `Border Classes=SurfaceCard` → `ItemsControl ItemsSource=Choices` con template:

```xml
<DataTemplate DataType="vm:CategoryChoice">
    <StackPanel>
        <Border Classes="Separator" Margin="{Binding SeparatorMargin}" IsVisible="{Binding ShowSeparator}" />
        <!-- Tutta la riga commuta la casella: un ToggleButton trasparente con la CheckBox non interattiva dentro. -->
        <ToggleButton Classes="ChoiceRow" IsChecked="{Binding IsSelected}" Padding="{Binding RowPadding}"
                      AutomationProperties.Name="{Binding DisplayName}">
            <Grid ColumnDefinitions="Auto,Auto,*,Auto" ColumnSpacing="12">
                <CheckBox IsChecked="{Binding IsSelected}" IsHitTestVisible="False" Focusable="False" VerticalAlignment="Center" />
                <Border Grid.Column="1" Classes="Tile" Background="{Binding TileBrush}" VerticalAlignment="Center">
                    <Viewbox Width="16" Height="16"><Path Classes="Icon" Data="{Binding Icon}" Stroke="White" /></Viewbox>
                </Border>
                <StackPanel Grid.Column="2" Spacing="2" VerticalAlignment="Center">
                    <TextBlock Text="{Binding DisplayName}" Classes="RowTitle" />
                    <TextBlock Text="{Binding Description}" Classes="RowDescription" />
                </StackPanel>
                <Border Grid.Column="3" Classes="RiskPill" Classes.Low="{Binding IsLowRisk}" Classes.Medium="{Binding IsMediumRisk}" Classes.High="{Binding IsHighRisk}" VerticalAlignment="Center">
                    <TextBlock Text="{Binding RiskLabel}" />
                </Border>
            </Grid>
        </ToggleButton>
    </StackPanel>
</DataTemplate>
```

  Stili locali `ToggleButton.ChoiceRow`: `Background=Transparent`, `BorderThickness=0`, `CornerRadius=0`, `HorizontalAlignment=Stretch`, `HorizontalContentAlignment=Stretch`, `MinHeight=0`; `:pointerover /template/ ContentPresenter` → `HoverBrush`; `:checked /template/ ContentPresenter` e `:checked:pointerover` → `Background` rispettivamente `Transparent` e `HoverBrush`, `Foreground=PrimaryTextBrush` (FluentTheme altrimenti colora lo stato checked di accento); `:focus-visible /template/ ContentPresenter` → bordo 2 `AccentBrush`.
  Barra azioni:

```xml
<Grid ColumnDefinitions="Auto,Auto,*,Auto,Auto" ColumnSpacing="12">
    <Viewbox Width="15" Height="15" VerticalAlignment="Center"><Path Classes="Icon" Data="{StaticResource IconShield}" Stroke="{DynamicResource SecondaryTextBrush}" /></Viewbox>
    <TextBlock Grid.Column="1" Text="L'analisi non elimina alcun file." Classes="Muted" FontSize="12" VerticalAlignment="Center" />
    <TextBlock Grid.Column="3" Text="{Binding SelectedCountText}" Classes="Muted Numeric" FontSize="12" VerticalAlignment="Center" />
    <Button Grid.Column="4" Classes="Primary" Command="{Binding AnalyzeCommand}" Padding="14,5,12,5">
        <StackPanel Orientation="Horizontal" Spacing="6">
            <TextBlock Text="Analizza" />
            <Viewbox Width="12" Height="12" VerticalAlignment="Center"><Path Classes="Icon" Data="{StaticResource IconChevronRight}" Stroke="White" StrokeThickness="2.4" /></Viewbox>
        </StackPanel>
    </Button>
</Grid>
```

  Nota testo: «Analizza →» diventa «Analizza» + chevron (stesso testo, freccia come icona del canvas).
- [ ] **Step 8: `ScanStepView`** — toolbar passo 2; contenuto: `PageTitle` «Analisi in corso…»; card `SurfaceCard Padding=18` invariata nei contenuti (testo, `ProgressBar Height=6`, percorso, errore con `Foreground=DangerBrush`); card categorie: `TextBlock "CATEGORIE"` diventa `TextBlock Classes=Eyebrow Text="CATEGORIE" Margin="16,12,16,4"` e righe `Grid Margin="16,9"` con separatori `Border.Separator Margin="16,0,0,0"` fra le righe (via `ItemsControl` + template con separatore in testa, saltato sulla prima con lo stile `ItemsControl.Rows > ContentPresenter:nth-child(1) Border.Separator { IsVisible=False }`); «Nessun file è stato ancora toccato.» resta sotto. Barra azioni: `StackPanel Orientation=Horizontal HorizontalAlignment=Right Spacing=10` con i due pulsanti esistenti invariati (Annulla / Torna al passo 1).
- [ ] **Step 9: `ConfirmStepView`** — toolbar passo 3; contenuto: `PageTitle` «Verifica prima di eliminare», `PageSubtitle {TotalText}`; `ItemsControl Nodes` con `Expander` (stili globali) invariati, `ListBox MaxHeight=360` e commento esistente conservati. Sopra la barra azioni, `StackPanel DockPanel.Dock=Bottom Margin="32,0,32,12" Spacing=10` con: `Border Classes=Banner` (testo «Eliminazione definitiva…» SemiBold, niente colori letterali), `RunningAppsWarning`, `ExclusionsText`, `DeleteErrorText` (`DangerBrush`). Barra azioni: `Grid ColumnDefinitions="*,Auto"` → `TextBlock {DeleteProgressText} IsVisible=IsDeleting Classes=Muted FontSize=12`, e a destra i pulsanti esistenti (Ricomincia, Interrompi, `Destructive` «Elimina {0}»). Ordine nel `DockPanel`: Toolbar (Top), ActionBar (Bottom), pannello avvisi (Bottom), ScrollViewer.
- [ ] **Step 10: `DoneStepView`** — toolbar passo 4; contenuto centrato invariato (cerchio `SuccessSurfaceBrush`/`SuccessBrush` con `Path IconCheck` 24 `Stroke=SuccessBrush StrokeThickness=2.4` al posto del carattere «✓», `PageTitle` «Pulizia completata», importo 32 Bold, riepilogo, card righe `SurfaceCard Padding=14 MaxWidth=600`). `ErrorsText` e `HistoryWarning` sopra la barra azioni (`Margin="32,0,32,12"`); barra azioni con `Button Classes=Primary "Nuova pulizia"` a destra.
- [ ] **Step 11: test di layout** — il test esistente sul contenuto lungo resta la garanzia che la barra azioni non esca dal viewport (i ViewModel del wizard richiedono `AppServices`, quindi le view si verificano senza DataContext). Aggiungere in `MainWindowLayoutTests`:

```csharp
[AvaloniaFact]
public void WizardViewsHaveToolbarAndActionBar()
{
    foreach (UserControl view in new UserControl[] { new ChooseStepView(), new ScanStepView(), new ConfirmStepView(), new DoneStepView() })
    {
        Window window = new() { Width = 888, Height = 700, Content = view };
        window.Show();
        window.UpdateLayout();
        Assert.Contains(view.GetVisualDescendants().OfType<Border>(), b => b.Classes.Contains("Toolbar"));
        Assert.Contains(view.GetVisualDescendants().OfType<Border>(), b => b.Classes.Contains("ActionBar"));
        Assert.Contains(view.GetVisualDescendants().OfType<StepIndicator>(), s => s.CurrentStep >= 1);
        window.Close();
    }
}
```
- [ ] **Step 12:** `dotnet test` → PASS; prova manuale di un ciclo completo con una sola categoria piccola (es. Log) fino al passo 3, poi «Ricomincia» (nessuna eliminazione durante lo sviluppo).
- [ ] **Step 13:** commit `feat(ui): restyle cleanup wizard with toolbar, grouped list and action bar`.

---

### Task 6: Docker e Xcode

**Files:**
- Modify: `src/MjmCleaner.App/Views/DockerView.axaml`, `DockerReportView.axaml`, `XcodeView.axaml`, `XcodeReportView.axaml`
- Test: `tests/MjmCleaner.App.Tests/ToolPagesLayoutTests.cs` (nuovo); i test in `tests/MjmCleaner.App.Tests/Xcode/XcodeViewLayoutTests.cs` devono continuare a passare senza modifiche.

**Interfaces:**
- Consumes: classi di stile del Task 2; nessuna modifica ai ViewModel.

- [ ] **Step 1: test che falliscono** — `ToolPagesLayoutTests.cs`:

```csharp
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.VisualTree;
using MjmCleaner.App.Tests.Xcode;
using MjmCleaner.App.ViewModels;
using MjmCleaner.App.Views;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class ToolPagesLayoutTests
{
    [AvaloniaFact]
    public async Task XcodePageHasToolbarAndNoCloseButton()
    {
        XcodeViewModel vm = new(new XcodeViewModelTests.FakeXcode(XcodeViewModelTests.Snapshot(
                XcodeViewModelTests.Candidate("derived", Core.Xcode.XcodeResourceKind.DerivedData))),
            new XcodeViewModelTests.FakeHistory(), new XcodeViewModelTests.FakeLog(), new XcodeViewModelTests.FakeNavigation());
        await vm.InitialLoad;
        Window window = new() { Width = 888, Height = 700, Content = new XcodeView { DataContext = vm } };
        window.Show();
        window.UpdateLayout();

        Assert.Contains(window.GetVisualDescendants().OfType<Border>(), b => b.Classes.Contains("Toolbar"));
        Assert.DoesNotContain(window.GetVisualDescendants().OfType<Button>(), b => b.Content as string == "Chiudi");
    }

    [AvaloniaFact]
    public void DockerViewsHaveNoCloseButton()
    {
        foreach (UserControl view in new UserControl[] { new DockerView(), new DockerReportView(), new XcodeReportView() })
        {
            Window window = new() { Width = 888, Height = 700, Content = view };
            window.Show();
            window.UpdateLayout();
            Assert.Contains(view.GetVisualDescendants().OfType<Border>(), b => b.Classes.Contains("Toolbar"));
            Assert.DoesNotContain(view.GetLogicalDescendantsOfType<Button>(), b => b.Content as string == "Chiudi");
            window.Close();
        }
    }
}

file static class LogicalExtensions
{
    public static IEnumerable<T> GetLogicalDescendantsOfType<T>(this Avalonia.LogicalTree.ILogical root)
        => Avalonia.LogicalTree.LogicalExtensions.GetLogicalDescendants(root).OfType<T>();
}
```

  (I pulsanti nascosti da `IsVisible` restano nell'albero logico: il test li trova anche senza DataContext.) Se `FakeXcode`, `Snapshot`, `Candidate`, `FakeHistory`, `FakeLog`, `FakeNavigation` non sono `public`/`internal` accessibili, renderli `internal` in `XcodeViewModelTests`.
- [ ] **Step 2:** `dotnet test --filter ToolPagesLayoutTests` → FAIL (pulsanti «Chiudi» presenti, nessuna toolbar).
- [ ] **Step 3: `DockerView`**
  - Toolbar: `Grid ColumnDefinitions="*,Auto"`; a sinistra `ToolbarTitle` «Pulizia Docker» e `ToolbarSubtitle` «Anteprima: nulla viene eliminato finché non premi «Elimina».»; a destra `Border Classes=StatusPill IsVisible="{Binding HasError}"` con `StackPanel Orientation=Horizontal Spacing=6`: `Ellipse Width=7 Height=7 Fill=#8E8E93` (animazione opacità 1→0.35, 1,6 s, `IterationCount=Infinite`, `PlaybackDirection=Alternate`) e `TextBlock "Motore non raggiungibile"`. Rimuovere l'eyebrow «DOCKER» e il vecchio titolo di pagina.
  - Stato errore (centrato, `Width=380`, `Margin="0,-24,0,0"`, `Spacing=14`): `Border Width=72 Height=72 CornerRadius=18 Background=WellBrush` con `Viewbox 36` → `Path Classes=Icon Data=IconCube Stroke=SecondaryTextBrush StrokeThickness=1.4`; `TextBlock {ErrorText} FontSize=17 FontWeight=SemiBold TextWrapping=Wrap TextAlignment=Center`; `Button Classes=Primary "Riprova" Command=RetryCommand HorizontalAlignment=Center Margin="0,6,0,0"`.
  - Caricamento: invariato (ProgressBar + testo).
  - Pronto: card info (`SurfaceCard Padding="16,12"`) e `Expander` per gruppo invariati nei contenuti, dentro `ScrollViewer` → `StackPanel Margin="32,24,32,20" Spacing=12`.
  - Sopra la barra azioni: `Banner` «Eliminazione definitiva: immagini e volumi…» (IsVisible=IsReady), `DeleteErrorText`. Barra azioni: a sinistra `DeleteProgressText` (IsVisible=IsDeleting), a destra Interrompi e «Elimina {0}» (`Destructive`, IsVisible=IsReady). Pulsante «Chiudi» rimosso.
- [ ] **Step 4: `DockerReportView`** — toolbar «Pulizia Docker» + sottotitolo `{SummaryText}`; contenuto: blocco centrato (`PageTitle` «Pulizia Docker completata», `FreedText` 32 Bold, card df/disco), banner `DaemonLostText` e `PurgeHint` con `Classes=Banner`, card «Eliminate» e «Non eliminate» (`DangerBrush`). `HistoryWarning` sopra la barra; barra azioni con `Primary` «Nuova analisi». «Chiudi» rimosso.
- [ ] **Step 5: `XcodeView`** — toolbar: `ToolbarTitle` «Pulizia cache e simulatori», `ToolbarSubtitle` «Tutte le voci partono deselezionate. L’anteprima non elimina nulla.» (testi esistenti spostati dalla testata). Contenuto: card `TotalText`, `Expander` di gruppo invariati. Il pannello di conferma resta sopra la barra azioni (`Margin="32,0,32,12"`) con `Classes=Banner`, `MaxHeight=330`, scroll interno `MaxHeight=220` e i suoi due pulsanti «Torna alla selezione» / «Conferma ed elimina» invariati (i test di layout li cercano per testo). Barra azioni: a sinistra `ProgressText` (IsDeleting), a destra Interrompi, «Riprova analisi», `Primary` «Anteprima selezione». `WarningText` ed `ErrorText` sopra la barra. «Chiudi» rimosso.
- [ ] **Step 6: `XcodeReportView`** — toolbar «Report pulizia» + `{SummaryText}`; righe risultato in un unico `SurfaceCard` con separatori (`Border.Separator Margin="16,0,0,0"`, padding riga `16,10`) invece di card separate; `FreedText`, `FreeSpaceText`, avvisi sopra la barra; barra con `Primary` «Nuova analisi Xcode». «Chiudi» rimosso.
- [ ] **Step 7:** `dotnet test` → PASS (inclusi `XcodeViewLayoutTests`: i controlli finali restano nel viewport con 100 voci).
- [ ] **Step 8:** prova manuale: Docker con Docker Desktop spento (stato vuoto, pill, Riprova) e acceso (solo analisi, nessuna eliminazione); Xcode fino all'anteprima, poi «Torna alla selezione».
- [ ] **Step 9:** commit `feat(ui): restyle Docker and Xcode pages`.

---

### Task 7: Storico

**Files:**
- Create: `src/MjmCleaner.App/ViewModels/CategoryNames.cs`
- Modify: `src/MjmCleaner.App/ViewModels/HistoryViewModel.cs`, `src/MjmCleaner.App/Views/HistoryView.axaml`, `src/MjmCleaner.App/Styles/MacTheme.axaml` (rimozione alias)
- Test: `tests/MjmCleaner.App.Tests/HistoryTests.cs` (nuovo)

**Interfaces:**
- Produces: `static IReadOnlyDictionary<string, string> CategoryNames.Build(IEnumerable<CleanupCategory> catalog)`.
- Produces: `HistoryRow(CleanSessionSummary session, IReadOnlyDictionary<string, string> names)` con `When`, `Freed`, `Items` (solo numero, `N0` it-IT), `IReadOnlyList<string> CategoryNames`, `Failed`; `HistoryViewModel.TotalText` (es. «9,5 GB»), `HistoryViewModel.CountText` (es. «in 1 pulizia»), `static string HistoryViewModel.Summarize(int count)`.

- [ ] **Step 1: test che falliscono** — `HistoryTests.cs`:

```csharp
using MjmCleaner.App.ViewModels;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.History;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class HistoryTests
{
    private static readonly IReadOnlyDictionary<string, string> Names = CategoryNames.Build(
        [new CleanupCategory("system-caches", "Cache utente e di sistema", "", RiskLevel.Medium, true, null, [])]);

    private static CleanSessionSummary Session(params string[] ids) => new(
        1,
        new DateTimeOffset(new DateTime(2026, 9, 26, 1, 19, 0, DateTimeKind.Local)),
        TimeSpan.FromSeconds(3),
        10_200_547_328,
        2117,
        0,
        [.. ids.Select(id => new CategoryCleanResult(id, 1, 1))]);

    [Fact]
    public void DateIsLocalisedItalian() => Assert.Equal("26 set 2026, 01:19", new HistoryRow(Session("system-caches"), Names).When);

    [Fact]
    public void ItemsUseThousandsSeparator() => Assert.Equal("2.117", new HistoryRow(Session("system-caches"), Names).Items);

    [Fact]
    public void CategoriesShowReadableNames()
    {
        HistoryRow row = new(Session("system-caches", "docker-images", "xcode-derived-data", "trash-downloads-large", "sconosciuta"), Names);
        Assert.Equal(["Cache utente e di sistema", "Immagini Docker", "DerivedData", "Cestino, Download e file grandi", "sconosciuta"], row.CategoryNames);
    }

    [Theory]
    [InlineData(0, "nessuna pulizia")]
    [InlineData(1, "in 1 pulizia")]
    [InlineData(4, "in 4 pulizie")]
    public void SummaryAgrees(int count, string expected) => Assert.Equal(expected, HistoryViewModel.Summarize(count));
}
```

  Verificare la firma reale di `CategoryCleanResult` in `src/MjmCleaner.Core/Cleaning/CleanModels.cs` e adattare la costruzione.
- [ ] **Step 2:** `dotnet test --filter HistoryTests` → FAIL.
- [ ] **Step 3: `CategoryNames.cs`**

```csharp
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.App.ViewModels;

/// <summary>
/// Nomi leggibili per gli identificativi salvati nello storico: il catalogo corrente,
/// le categorie di Docker e Xcode e gli ID di versioni precedenti del catalogo.
/// </summary>
public static class CategoryNames
{
    private static readonly Dictionary<string, string> Fixed = new(StringComparer.Ordinal)
    {
        [DockerCategories.Images] = "Immagini Docker",
        [DockerCategories.Volumes] = "Volumi Docker",
        [DockerCategories.BuildCache] = "Cache di build Docker",
        ["xcode-derived-data"] = "DerivedData",
        ["xcode-device-support"] = "Device Support",
        ["xcode-simulator-devices"] = "Dispositivi simulati",
        ["xcode-runtimes"] = "Runtime dei simulatori",
        ["trash-downloads-large"] = "Cestino, Download e file grandi",
    };

    public static IReadOnlyDictionary<string, string> Build(IEnumerable<CleanupCategory> catalog)
    {
        Dictionary<string, string> names = new(Fixed, StringComparer.Ordinal);
        foreach (CleanupCategory category in catalog) names[category.Id] = category.DisplayName;
        return names;
    }
}
```

- [ ] **Step 4: `HistoryViewModel.cs`**

```csharp
public sealed class HistoryRow(CleanSessionSummary session, IReadOnlyDictionary<string, string> names)
{
    private static readonly CultureInfo Italian = new("it-IT");

    /// <summary>I timestamp sono salvati in UTC e resi in ora locale: altrimenti il cambio d'ora riordina lo storico.</summary>
    public string When { get; } = session.StartedAtUtc.ToLocalTime().ToString("d MMM yyyy, HH:mm", Italian);

    public long BytesFreed { get; } = session.BytesFreed;
    public string Freed { get; } = ViewModelBase.FormatBytes(session.BytesFreed);
    public string Items { get; } = session.ItemsDeleted.ToString("N0", Italian);
    public IReadOnlyList<string> CategoryNames { get; } =
        [.. session.Categories.Select(c => names.GetValueOrDefault(c.CategoryId, c.CategoryId))];
    public string Failed { get; } = session.ItemsFailed == 0 ? string.Empty : $"{session.ItemsFailed} falliti";
}

public sealed partial class HistoryViewModel : ViewModelBase
{
    private readonly MainWindowViewModel _main;

    [ObservableProperty] private string _totalText = "—";
    [ObservableProperty] private string _countText = string.Empty;

    public HistoryViewModel(AppServices services, MainWindowViewModel main)
    {
        _main = main;
        _ = LoadAsync(services);
    }

    public ObservableCollection<HistoryRow> Rows { get; } = [];

    public static string Summarize(int count) => count switch
    {
        0 => "nessuna pulizia",
        1 => "in 1 pulizia",
        _ => $"in {count} pulizie",
    };

    private async Task LoadAsync(AppServices services)
    {
        IReadOnlyList<CleanSessionSummary> sessions =
            await services.History.GetSessionsAsync(50, CancellationToken.None);
        IReadOnlyDictionary<string, string> names = ViewModels.CategoryNames.Build(services.BuildCategories());

        foreach (CleanSessionSummary session in sessions)
        {
            Rows.Add(new HistoryRow(session, names));
        }

        TotalText = FormatBytes(Rows.Sum(r => r.BytesFreed));
        CountText = Summarize(Rows.Count);
    }

    [RelayCommand]
    private void Close() => _main.StartOver();
}
```

  (`using System.Globalization;`, `using CommunityToolkit.Mvvm.ComponentModel;`; `partial` già presente.)
- [ ] **Step 5:** `dotnet test --filter HistoryTests` → PASS.
- [ ] **Step 6: `HistoryView.axaml`** — `DockPanel`:
  - Toolbar: sinistra `ToolbarTitle` «Storico delle pulizie» + `ToolbarSubtitle` «Le pulizie completate e lo spazio effettivamente recuperato.»; destra `StackPanel Orientation=Horizontal Spacing=6` con `TextBlock {TotalText} FontSize=13 FontWeight=SemiBold Classes=Numeric` e `TextBlock {CountText} FontSize=12 Classes=Muted`.
  - Fill: `Border Classes=SurfaceCard Margin="24,20,24,24"` → `DockPanel`:
    - Top: intestazione `Grid ColumnDefinitions="210,110,*,120" Height=30 Margin="16,0"` + `Border.Separator` sotto; celle 11/SemiBold `SecondaryTextBrush`: «Data» (`PrimaryTextBrush` + `Path IconChevronDown`? usare `Path Data="M6 9 L12 15 L18 9"` 9×9 `StrokeThickness=3`), «Spazio» (`HorizontalAlignment=Right Margin="0,0,24,0"`), «Categorie» (`Border BorderThickness="0.5,0,0,0" BorderBrush=SeparatorBrush Padding="12,0,0,0"`), «Elementi» (destra).
    - Fill: `Panel` con, in fondo, `Border Background="{StaticResource HistoryStripes}"` (riempimento a strisce fino al fondo) e sopra `ScrollViewer` → `ItemsControl Classes=Striped ItemsSource=Rows` (le righe sono opache: dispari `GroupBrush`, pari `StripeBrush`; lo sfondo a strisce resta visibile solo sotto l'ultima riga).
    - Riga (`DataTemplate vm:HistoryRow`): `Grid ColumnDefinitions="210,110,*,120" Height=32 Margin="16,0"`: `When` (`Numeric`), `Freed` (SemiBold, destra, `Margin="0,0,24,0"`, `Numeric`), `ItemsControl CategoryNames` orizzontale `Spacing=6` `Margin="12,0,0,0"` con chip `Border CornerRadius=5 Padding="8,2" Background=WellBrush` → `TextBlock FontSize=11 FontWeight=Medium TextTrimming=CharacterEllipsis`, `Items` (destra, `Muted Numeric`). Stato vuoto invariato: lo storico vuoto mostra solo intestazione e strisce.
  - Risorsa `HistoryStripes` in `UserControl.Resources` (periodo 64: riga 0 trasparente, riga 1 striscia, allineato all'alto):
    ```xml
    <DrawingBrush x:Key="HistoryStripes" TileMode="Tile" Stretch="None" AlignmentX="Left" AlignmentY="Top" DestinationRect="0,0,8,64" SourceRect="0,0,8,64">
        <DrawingBrush.Drawing>
            <DrawingGroup>
                <GeometryDrawing Brush="{DynamicResource GroupBrush}" Geometry="M0,0 H8 V32 H0 Z" />
                <GeometryDrawing Brush="{DynamicResource StripeBrush}" Geometry="M0,32 H8 V64 H0 Z" />
            </DrawingGroup>
        </DrawingBrush.Drawing>
    </DrawingBrush>
    ```
    Se `DestinationRect` viene interpretato come relativo (strisce non da 32 px nello screenshot), sostituire il riempimento con `ItemsControl` di 30 righe vuote alte 32 sotto le righe reali (stessa classe `Striped`, indice proseguito: `HistoryViewModel.FillerRows` = `Enumerable.Range(Rows.Count, 30)`), dentro lo stesso `StackPanel` delle righe, con `ClipToBounds` sulla card.
  - Rimuovere il pulsante «Chiudi».
- [ ] **Step 7: pulizia alias** — togliere da `MacTheme.axaml` gli alias `CanvasBrush`, `ToolbarBrush`, `CardBrush`, `BorderBrush`, `SubtleSurfaceBrush`; `grep -rn 'CanvasBrush\|ToolbarBrush\|CardBrush\|"{DynamicResource BorderBrush}"\|SubtleSurfaceBrush\|#[0-9A-Fa-f]\{6\}' src/MjmCleaner.App/Views` deve restituire solo i colori delle anteprime Aspetto e `#8E8E93` del pallino Docker.
- [ ] **Step 8:** `dotnet test` → PASS; prova manuale dello Storico con dati reali (nomi leggibili, data «26 set 2026, 01:19», strisce fino al fondo, nessun «Chiudi»).
- [ ] **Step 9:** commit `feat(ui): native-style history table with readable categories`.

---

### Task 8: Verifica finale e screenshot

**Files:**
- Create: `docs/superpowers/verification/2026-10-02-macos-redesign.md`, `docs/superpowers/verification/2026-10-02-macos-redesign/*.png`
- Scratch (non versionato): progetto di cattura in `$SCRATCHPAD/shots/`

- [ ] **Step 1: suite completa** — `dotnet build` (0 avvisi nuovi) e `dotnet test` → riportare i totali.
- [ ] **Step 2: screenshot dell'app reale** — avviare `dotnet run --project src/MjmCleaner.App`; per ogni schermata (Scegli, Analizza, Conferma, Docker non raggiungibile, Xcode, Storico, Impostazioni) e per Chiaro e Scuro (cambiati dalla finestra Impostazioni, senza salvare oppure salvando e ripristinando `Automatico` alla fine) catturare la finestra con `screencapture -o -l <windowid> file.png`, ricavando l'id con `osascript -e 'tell application "System Events" to …'` o, se non disponibile, `screencapture -o -w` interattivo. Se la cattura non è permessa (Registrazione schermo), usare lo Step 3 come fonte principale e dichiararlo.
- [ ] **Step 3: screenshot headless deterministici** — progetto console scratch che referenzia `MjmCleaner.App`, `Avalonia.Headless` e `Avalonia.Skia`:

```csharp
AppBuilder.Configure<App>().UseSkia().UseHeadless(new AvaloniaHeadlessPlatformOptions { UseHeadlessDrawing = false })
    .With(new FontManagerOptions { DefaultFamilyName = ".AppleSystemUIFont" })
    .SetupWithoutStarting();
foreach (ThemeVariant theme in new[] { ThemeVariant.Light, ThemeVariant.Dark })
{
    Application.Current!.RequestedThemeVariant = theme;
    // per ogni view: Window 1120×700 (Impostazioni 700×820), DataContext con dati d'esempio,
    // window.Show(); Dispatcher.UIThread.RunJobs(); window.CaptureRenderedFrame()!.Save($"{name}-{theme}.png");
}
```

  Dati d'esempio: `ChooseStepView` con le categorie del catalogo (via `AppServices.CreateAsync()` reale: sola lettura), `XcodeView` con i fake di `XcodeViewModelTests`, `SettingsWindow` con `MemoryStore`, `HistoryView` con lo storico reale, `MainWindow` intera per sidebar e Docker (Docker spento o acceso: l'analisi è in sola lettura).
- [ ] **Step 4: confronto col canvas** — per ogni schermata affiancare lo screenshot al board del canvas (`Main`, `Docker`, `Storico`, `Impostazioni`) e annotare le differenze; correggere quelle di misura/colore prima di chiudere.
- [ ] **Step 5: checklist §7 dell'handoff** — compilare nel documento di verifica, voce per voce, con evidenza (test, screenshot, comando):
  1. Nessun flusso, passo o azione aggiunto o rimosso (elenco comandi per view prima/dopo).
  2. Sidebar sostituisce le schede; nessun «Chiudi» (test `ShellHasSidebarAndNoCloseButtons`, `ToolPagesLayoutTests`).
  3. Impostazioni in finestra propria, ⌘, funzionante (prova manuale + menu).
  4. Token §2 applicati, chiaro e scuro (screenshot + `ThemeTests`).
  5. Aspetto Automatico/Chiaro/Scuro funzionante e persistente; `auto` segue il sistema in tempo reale (cambio di Aspetto di sistema con l'app aperta: `osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode'`, poi ripristino).
  6. Storico con nomi leggibili e date localizzate (`HistoryTests` + screenshot).
  7. Screenshot di ogni schermata in chiaro e scuro confrontati col canvas.
- [ ] **Step 6:** commit `docs(ui): record macOS redesign verification`.

---

## Self-review

- **Copertura spec:** decisioni (Xcode in sidebar → T3; dimensioni → T3; Impostazioni modale/Salva/Annulla → T4; liste cartelle → T4; tre età → T4; messaggio Docker → T6; voce Pulizia → T3; blocco navigazione → T3 invariato; accento → T2; niente vibrancy → T3 colore pieno; tile `downloads-large` → T5). Mappatura schermate → T3–T7. Aspetto → T1, T2, T4. Storico → T7. Testi nuovi → T3 (sidebar), T4, T5, T6, T7. Accessibilità → `AutomationProperties.Name` su +/−, radio e righe (T4, T5), focus visibile (T2, T5). Verifica → T8.
- **Placeholder:** i soli rimandi sono alle firme di `CleanupCategory` e `CategoryCleanResult`, da verificare nel file indicato prima di scrivere il test.
- **Coerenza tipi:** `IAppearanceController.Apply`, `IFolderPicker.PickFolderAsync`, `SettingsViewModel(ISettingsStore, IAppearanceController, IFolderPicker, Action)`, `SidebarSections.For/IsWizardPage`, `CategoryVisuals.For(...).TileColor/IconData`, `CategoryNames.Build`, `HistoryRow(session, names)` usati con le stesse firme in tutti i task.
