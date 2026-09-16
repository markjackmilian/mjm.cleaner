#!/usr/bin/env bash
# Costruisce artifacts/mjm.cleaner.app a partire dalla pubblicazione self-contained.
set -euo pipefail

export PATH="/usr/local/share/dotnet:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/artifacts/mjm.cleaner.app"
ARCH="$(uname -m)"
RID="osx-arm64"
[ "$ARCH" = "x86_64" ] && RID="osx-x64"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

dotnet publish "$ROOT/src/MjmCleaner.App" \
    --configuration Release \
    --runtime "$RID" \
    --self-contained true \
    --output "$APP/Contents/MacOS"

cp "$ROOT/build/Info.plist" "$APP/Contents/Info.plist"

# Firma ad-hoc: senza una firma macOS rifiuta di avviare il bundle.
codesign --force --deep --sign - "$APP"

echo "Creato: $APP"
echo "Nota: dopo ogni ricompilazione può essere necessario riconcedere l'Accesso completo al disco."
