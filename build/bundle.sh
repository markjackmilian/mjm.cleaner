#!/usr/bin/env bash
# Costruisce un bundle macOS self-contained per una singola architettura.
set -euo pipefail

export PATH="/usr/local/share/dotnet:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/build/bundle-config.sh"

ARCH="$(uname -m)"
DEFAULT_RID="osx-arm64"
[[ "$ARCH" == "x86_64" ]] && DEFAULT_RID="osx-x64"

RID="$DEFAULT_RID"
VERSION="1.0.0"
VERSION_WAS_SET=false
BUILD_NUMBER="1"
OUTPUT_DIR="$ROOT/artifacts"

usage() {
    cat <<'EOF'
Uso: ./build/bundle.sh [opzioni]

  --runtime RID         osx-arm64 oppure osx-x64 (default: architettura host)
  --version VERSIONE    versione applicazione, per esempio 1.2.3 (default: 1.0.0)
  --build-number NUMERO CFBundleVersion numerico (default: 1)
  --output-dir CARTELLA cartella degli artefatti (default: ./artifacts)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runtime) RID="${2:?Manca il valore per --runtime}"; shift 2 ;;
        --version) VERSION="${2:?Manca il valore per --version}"; VERSION_WAS_SET=true; shift 2 ;;
        --build-number) BUILD_NUMBER="${2:?Manca il valore per --build-number}"; shift 2 ;;
        --output-dir) OUTPUT_DIR="${2:?Manca il valore per --output-dir}"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Opzione non riconosciuta: $1" >&2; usage >&2; exit 2 ;;
    esac
done

VERSION="$(normalize_version "$VERSION")"
ARTIFACT_NAME="mjm.cleaner"
if [[ "$VERSION_WAS_SET" == true ]]; then
    ARTIFACT_NAME="$(artifact_basename "$RID" "$VERSION")"
fi

if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "Build number non valido: '$BUILD_NUMBER'" >&2
    exit 2
fi

APP="$OUTPUT_DIR/$ARTIFACT_NAME.app"
ZIP="$OUTPUT_DIR/$ARTIFACT_NAME.zip"

rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

"$ROOT/build/make-icon.sh" \
    "$ROOT/src/MjmCleaner.App/Assets/AppIcon-1024.png" \
    "$APP/Contents/Resources/AppIcon.icns"

dotnet publish "$ROOT/src/MjmCleaner.App" \
    --configuration Release \
    --runtime "$RID" \
    --self-contained true \
    --output "$APP/Contents/MacOS"

cp "$ROOT/build/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# Firma ad-hoc: senza una firma macOS rifiuta di avviare il bundle.
codesign --force --deep --sign - "$APP"

# ditto preserva permessi, extended attributes e struttura del bundle macOS.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "Creato: $APP"
echo "Creato: $ZIP"
echo "Nota: dopo ogni ricompilazione può essere necessario riconcedere l'Accesso completo al disco."
