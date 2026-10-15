#!/bin/zsh
# Screenshot delle pagine dell'avvio dimostrativo (solo Debug), in chiaro e in scuro (spec §9.4).
# Uso: swift/Scripts/screenshots.sh <cartella di uscita> [pagina…]
# Senza pagine le cattura tutte. Durante la cattura si aprono e si chiudono finestre dell'app.
set -euo pipefail

here=${0:A:h}
project=${here:h}/MjmCleaner.xcodeproj
out=${1:?"uso: screenshots.sh <cartella di uscita> [pagina…]"}
shift
if (( $# )); then
    pages=("$@")
else
    pages=(choose scan confirm done docker docker-unavailable docker-report xcode xcode-preview xcode-report history settings startup-failure)
fi
# Percorso risolto (/private/var/…): `pgrep -f` lo confronta con quello del processo avviato.
build=${${TMPDIR:-/tmp}:A}/mjm-cleaner-screenshots

mkdir -p "$out" "$build"
xcodebuild -project "$project" -scheme MjmCleaner -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$build" -quiet build
swiftc -O "$here/window-id.swift" -o "$build/window-id"
bundle="$build/Build/Products/Debug/MjmCleaner.app"
binary="$bundle/Contents/MacOS/MjmCleaner"

for page in $pages; do
    for appearance in light dark; do
        # `open` avvia l'app da LaunchServices, come il Finder: un processo figlio di questa shell
        # potrebbe non ricevere finestre.
        open -n "$bundle" --args -MJMDemo "$page" -MJMAppearance "$appearance"
        # Il tempo per caricare la pagina e, per le Impostazioni, aprire lo sheet.
        sleep 3
        pid=$(pgrep -n -f "$binary" || true)
        if [[ -n $pid ]] && id=$("$build/window-id" "$pid" 10); then
            screencapture -x -o -l"$id" "$out/$page-$appearance.png"
            print "$out/$page-$appearance.png"
        else
            print -u2 "nessuna finestra per $page ($appearance)"
        fi
        [[ -n $pid ]] && kill "$pid" 2>/dev/null || true
        sleep 1
    done
done
