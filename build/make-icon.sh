#!/usr/bin/env bash
# Converte l'icona sorgente PNG in un bundle .icns nativo per macOS.
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Uso: $0 <sorgente.png> <destinazione.icns>" >&2
    exit 64
fi

SOURCE="$1"
DESTINATION="$2"
ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/mjm-cleaner-icon.XXXXXX.iconset")"

cleanup() {
    rm -rf "$ICONSET"
}
trap cleanup EXIT

[ -f "$SOURCE" ]
mkdir -p "$(dirname "$DESTINATION")"

resize() {
    local size="$1"
    local name="$2"
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/$name" >/dev/null
}

resize 16 icon_16x16.png
resize 32 icon_16x16@2x.png
resize 32 icon_32x32.png
resize 64 icon_32x32@2x.png
resize 128 icon_128x128.png
resize 256 icon_128x128@2x.png
resize 256 icon_256x256.png
resize 512 icon_256x256@2x.png
resize 512 icon_512x512.png
resize 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$DESTINATION"
