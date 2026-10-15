#!/bin/zsh
# Screenshot delle pagine dell'avvio dimostrativo (solo Debug), in chiaro e in scuro (spec §9.4).
# Uso: swift/Scripts/screenshots.sh <cartella di uscita> [pagina…]
# Senza pagine le cattura tutte. Durante la cattura si aprono e si chiudono finestre dell'app.
# Esce con 1 se una cattura non riesce (per esempio con lo schermo bloccato o spento).
set -euo pipefail

here=${0:A:h}
project=${here:h}/MjmCleaner.xcodeproj
out=${1:?"uso: screenshots.sh <cartella di uscita> [pagina…]"}
shift

# Le pagine di `DemoLaunch.Page`. Con una pagina sconosciuta l'app partirebbe senza la demo, cioè
# con i dati veri dell'utente: si rifiuta prima di avviare qualunque cosa.
all=(choose scan confirm done docker docker-unavailable docker-report xcode xcode-preview xcode-report history settings startup-failure)
if (( $# )); then
    pages=("$@")
else
    pages=($all)
fi
for page in $pages; do
    if (( ! ${all[(Ie)$page]} )); then
        print -u2 "pagina demo sconosciuta: $page"
        exit 2
    fi
done

# Percorso risolto (/private/var/…): `pgrep -f` lo confronta con quello del processo avviato.
build=${${TMPDIR:-/tmp}:A}/mjm-cleaner-screenshots

mkdir -p "$out" "$build"
xcodebuild -project "$project" -scheme MjmCleaner -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$build" -quiet build
swiftc -O "$here/window-id.swift" -o "$build/window-id"
bundle="$build/Build/Products/Debug/MjmCleaner.app"
binary="$bundle/Contents/MacOS/MjmCleaner"

# Senza la demo nel binario (un Debug senza la condizione DEBUG) ogni avvio sarebbe l'app vera.
demo=0
for file in "$binary" "$binary.debug.dylib"; do
    if [[ -f $file ]] && (( $(strings "$file" | grep -c MJMDemo || true) > 0 )); then
        demo=1
    fi
done
if (( ! demo )); then
    print -u2 "la demo non è nel binario Debug: nessuno screenshot"
    exit 1
fi

# L'app aperta si chiude anche se lo script si interrompe.
pid=""
trap '[[ -n $pid ]] && kill "$pid" 2>/dev/null; true' EXIT

failed=0
for page in $pages; do
    for appearance in light dark; do
        # `open` avvia l'app da LaunchServices, come il Finder: un processo figlio di questa shell
        # potrebbe non ricevere finestre.
        open -n "$bundle" --args -MJMDemo "$page" -MJMAppearance "$appearance"
        # Il tempo per caricare la pagina e, per le Impostazioni, aprire lo sheet.
        sleep 3
        pid=$(pgrep -n -f "$binary" || true)
        if [[ -n $pid ]] && id=$("$build/window-id" "$pid" 10); then
            if screencapture -x -o -l"$id" "$out/$page-$appearance.png"; then
                print "$out/$page-$appearance.png"
            else
                print -u2 "cattura non riuscita per $page ($appearance): lo schermo è bloccato o spento?"
                failed=1
            fi
        else
            print -u2 "nessuna finestra per $page ($appearance)"
            failed=1
        fi
        if [[ -n $pid ]]; then
            kill "$pid" 2>/dev/null || true
        fi
        pid=""
        sleep 1
    done
done
exit $failed
