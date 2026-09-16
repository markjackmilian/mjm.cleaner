using CommunityToolkit.Mvvm.ComponentModel;

namespace MjmCleaner.App.ViewModels;

public abstract class ViewModelBase : ObservableObject
{
    /// <summary>Formato leggibile con separatore decimale italiano: 11,3 GB.</summary>
    public static string FormatBytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        double value = bytes;
        int unit = 0;

        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }

        return unit == 0
            ? $"{bytes} {units[unit]}"
            : string.Format(new System.Globalization.CultureInfo("it-IT"), "{0:0.#} {1}", value, units[unit]);
    }

    /// <summary>Concordanza minima singolare/plurale: evita «1 elementi» quando <paramref name="count"/> è 1.</summary>
    public static string Plural(int count, string singular, string plural) => count == 1 ? singular : plural;
}
