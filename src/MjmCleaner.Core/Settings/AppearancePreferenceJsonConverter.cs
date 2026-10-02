using System.Text.Json;
using System.Text.Json.Serialization;

namespace MjmCleaner.Core.Settings;

/// <summary>
/// Legge l'aspetto senza mai far fallire il caricamento delle impostazioni: un file modificato a mano o
/// scritto da una versione diversa («Darkk», un numero, null) vale <see cref="AppearancePreference.Auto"/>
/// invece di buttare via anche tutte le altre impostazioni. Si scrive il nome, così il file resta leggibile.
/// </summary>
public sealed class AppearancePreferenceJsonConverter : JsonConverter<AppearancePreference>
{
    public override AppearancePreference Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.String)
        {
            // Solo i nomi: Enum.TryParse accetterebbe anche «1» come numero.
            string? text = reader.GetString();
            foreach (AppearancePreference candidate in Enum.GetValues<AppearancePreference>())
            {
                if (string.Equals(candidate.ToString(), text, StringComparison.OrdinalIgnoreCase)) return candidate;
            }

            return AppearancePreference.Auto;
        }

        // Oggetti e array vanno consumati per intero, altrimenti il lettore resterebbe a metà del valore.
        reader.Skip();
        return AppearancePreference.Auto;
    }

    public override void Write(Utf8JsonWriter writer, AppearancePreference value, JsonSerializerOptions options)
        => writer.WriteStringValue(value.ToString());
}
