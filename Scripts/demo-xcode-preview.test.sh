#!/usr/bin/env bash
# Prova che l'anteprima Xcode dell'avvio dimostrativo (`-MJMDemo xcode-preview`) riesce con i dati
# fissi di `DemoData.swift`: ogni cartella selezionabile deve avere la sua voce nell'inventario dei
# file protetto, altrimenti `XcodeSelection.preview` rifiuta la selezione (difetto V-01).
# Esiste come script perché il package non vede i file dell'app e il progetto Xcode non ha target di
# test: costruisce CleanerCore e compila `DemoData.swift` insieme a `DemoXcodePreviewTest.swift`.
# Uso: Scripts/demo-xcode-preview.test.sh
# `CLEANER_CORE_BUILD_DIR` sostituisce la cartella dei prodotti del package, se serve.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWIFT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$SWIFT_ROOT/MjmCleanerKit"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/mjm-demo-xcode-preview.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT

swift build --package-path "$PACKAGE_DIR" --product CleanerCore
BIN_DIR="${CLEANER_CORE_BUILD_DIR:-$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)}"

if [[ ! -f "$BIN_DIR/libCleanerCore.a" || ! -d "$BIN_DIR/CleanerCore.swiftmodule" ]]; then
  printf 'CleanerCore build products not found in %s; set CLEANER_CORE_BUILD_DIR after building the package.\n' "$BIN_DIR" >&2
  exit 2
fi

swiftc \
  -module-cache-path "$TEST_TMP/module-cache" \
  -DDEBUG \
  -I "$BIN_DIR" \
  -I "$PACKAGE_DIR/Sources/CZlib" \
  -L "$BIN_DIR" \
  -lCleanerCore \
  "$SWIFT_ROOT/MjmCleaner/Demo/DemoData.swift" \
  "$SCRIPT_DIR/DemoXcodePreviewTest.swift" \
  -o "$TEST_TMP/DemoXcodePreviewTest"

PACKAGE_RESOURCE_BUNDLE_PATH="$BIN_DIR" "$TEST_TMP/DemoXcodePreviewTest"

printf 'PASS: demo Xcode preview\n'
