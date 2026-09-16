using System.Collections.ObjectModel;
using Avalonia;
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
        RiskLevel.Low => "rischio basso",
        RiskLevel.Medium => "rischio medio",
        RiskLevel.High => "rischio alto",
        _ => string.Empty,
    };

    /// <summary>I pacchetti NuGet compaiono rientrati sotto le cache di sviluppo.</summary>
    public Thickness Indent => Category.ParentId is null ? new Thickness(0) : new Thickness(28, 0, 0, 0);
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

        Choices = [.. services.BuildCategories().Select(category =>
            new CategoryChoice(category, remembered.Contains(category.Id)))];
    }

    public ObservableCollection<CategoryChoice> Choices { get; }

    [RelayCommand]
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
