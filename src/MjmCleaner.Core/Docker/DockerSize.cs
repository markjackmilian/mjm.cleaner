using System.Globalization;
using System.Text.RegularExpressions;

namespace MjmCleaner.Core.Docker;

/// <summary>
/// Converte le dimensioni testuali stampate dalla CLI ("195MB", "1.131kB", "76.74MB (2%)").
/// Docker usa unità DECIMALI (go-units HumanSize: 1 kB = 1000 B), non binarie: interpretarle
/// come potenze di 1024 gonfierebbe del 7% ogni dimensione in GB mostrata all'utente.
/// </summary>
public static partial class DockerSize
{
    private static readonly Dictionary<string, long> Multipliers = new(StringComparer.OrdinalIgnoreCase)
    {
        ["B"] = 1,
        ["kB"] = 1_000,
        ["MB"] = 1_000_000,
        ["GB"] = 1_000_000_000,
        ["TB"] = 1_000_000_000_000,
        ["PB"] = 1_000_000_000_000_000,
    };

    [GeneratedRegex(@"^\s*(?<value>\d+(?:\.\d+)?)\s*(?<unit>[kKMGTP]?B)\b")]
    private static partial Regex SizePattern();

    /// <summary>Null per "N/A", vuoto o testo non riconosciuto: una dimensione ignota non è zero.</summary>
    public static long? Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        Match match = SizePattern().Match(text);
        if (!match.Success
            || !Multipliers.TryGetValue(match.Groups["unit"].Value, out long multiplier)
            || !decimal.TryParse(match.Groups["value"].Value, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out decimal value))
        {
            return null;
        }

        return (long)Math.Round(value * multiplier);
    }
}
