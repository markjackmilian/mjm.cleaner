"""Scrive il catalogo asset dell'app (spec §6.4): accento, tile delle categorie, pill di rischio e la
voce dell'icona (il PNG si copia a parte). I file Contents.json generati sono quelli da committare.

Uso, dalla radice del repository: python3 -I Scripts/make-assets.py MjmCleaner/Assets.xcassets
"""
import json
import os
import sys

root = sys.argv[1]
INFO = {"author": "xcode", "version": 1}


def write(path, content):
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(content, f, indent=2)
        f.write("\n")


def color(argb):
    """"#RRGGBB" o "#AARRGGBB" → componenti sRGB."""
    hex = argb.lstrip("#")
    alpha = int(hex[:2], 16) / 255 if len(hex) == 8 else 1.0
    rgb = hex[-6:]
    return {
        "color-space": "srgb",
        "components": {
            "alpha": f"{alpha:.3f}",
            "red": "0x" + rgb[0:2],
            "green": "0x" + rgb[2:4],
            "blue": "0x" + rgb[4:6],
        },
    }


def colorset(name, light, dark=None):
    colors = [{"color": color(light), "idiom": "universal"}]
    if dark is not None:
        colors.append({
            "appearances": [{"appearance": "luminosity", "value": "dark"}],
            "color": color(dark),
            "idiom": "universal",
        })
    write(os.path.join(root, name + ".colorset"), {"colors": colors, "info": INFO})


write(root, {"info": INFO})
write(os.path.join(root, "AppIcon.appiconset"), {
    "images": [{"filename": "AppIcon-1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"}],
    "info": INFO,
})

# Accento del progetto: macOS lo usa con l'accento di sistema «multicolore».
colorset("AccentColor", "#0A66D8")

# Tile delle categorie: lo stesso colore in chiaro e in scuro, con il simbolo bianco.
for name, value in [
    ("TileSystemCaches", "#66788F"),
    ("TileDevCaches", "#7457E8"),
    ("TileNuGet", "#3567D0"),
    ("TileBuildOutput", "#1D8784"),
    ("TileTrash", "#D2453A"),
    ("TileDownloadsLarge", "#E8833A"),
    ("TileNeutral", "#85858B"),
]:
    colorset(name, value)

# Pill di rischio: testo e fondo, chiaro e scuro (MacTheme.axaml del C#).
for name, light, dark in [
    ("RiskLow", "#55555A", "#C7C7CC"),
    ("RiskLowBackground", "#0E000000", "#14FFFFFF"),
    ("RiskMedium", "#9E4700", "#FFB04D"),
    ("RiskMediumBackground", "#FFF0DE", "#29FF9F0A"),
    ("RiskHigh", "#B42318", "#FF8A80"),
    ("RiskHighBackground", "#FDECEA", "#2BFF453A"),
]:
    colorset(name, light, dark)
