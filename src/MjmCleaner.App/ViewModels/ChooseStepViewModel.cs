using System.Collections.ObjectModel;
using Avalonia;
using Avalonia.Media;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App.ViewModels;

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

public sealed partial class ChooseStepViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;

    public ChooseStepViewModel(AppServices services, MainWindowViewModel main)
    {
        _services = services;
        _main = main;

        CleanerSettings settings = services.Settings.Load();
        HashSet<string> remembered = new(settings.SelectedCategoryIds, StringComparer.Ordinal);

        Choices = [.. services.BuildCategories().Select((category, index) =>
            new CategoryChoice(category, remembered.Contains(category.Id)) { ShowSeparator = index > 0 })];
        foreach (CategoryChoice choice in Choices)
        {
            choice.PropertyChanged += (_, e) =>
            {
                if (e.PropertyName != nameof(CategoryChoice.IsSelected))
                {
                    return;
                }

                OnPropertyChanged(nameof(SelectedCount));
                OnPropertyChanged(nameof(SelectedCountText));
                AnalyzeCommand.NotifyCanExecuteChanged();
            };
        }
    }

    public ObservableCollection<CategoryChoice> Choices { get; }

    public int SelectedCount => Choices.Count(c => c.IsSelected);

    public string SelectedCountText => CountText(SelectedCount);

    public static string CountText(int count) => count switch
    {
        0 => "Nessuna categoria selezionata",
        1 => "1 categoria selezionata",
        _ => $"{count} categorie selezionate",
    };

    private bool CanAnalyze() => SelectedCount > 0;

    [RelayCommand(CanExecute = nameof(CanAnalyze))]
    private void Analyze()
    {
        CleanupCategory[] selected = [.. Choices.Where(c => c.IsSelected).Select(c => c.Category)];

        if (selected.Length == 0)
        {
            return;
        }

        // La selezione viene ricordata: è ciò che rende sopportabili quattro passi ogni settimana.
        CleanerSettings settings = _services.Settings.Load() with
        {
            SelectedCategoryIds = [.. selected.Select(c => c.Id)],
        };
        _services.Settings.Save(settings);

        _main.GoTo(new ScanStepViewModel(_services, _main, selected));
    }
}
