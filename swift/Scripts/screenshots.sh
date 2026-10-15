#!/bin/zsh
# Screenshot delle pagine dell'avvio dimostrativo (solo Debug), in chiaro e in scuro (spec §9.4).
# Uso: swift/Scripts/screenshots.sh <cartella di uscita> [pagina…]
# Senza pagine le cattura tutte. Durante la cattura si aprono e si chiudono finestre dell'app: non
# usare il Mac finché lo script non finisce (con Claude in primo piano), perché ogni finestra prende il
# primo piano e i tasti premuti finirebbero nella demo.
# Esce con 1 se una cattura non riesce (schermo bloccato o spento, oppure Mac in uso: una finestra
# che non arriva in primo piano non si cattura).
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

# Il pid dell'app in primo piano; `lsappinfo` legge soltanto, non attiva nulla.
front_pid() {
    local info
    info=$(lsappinfo info -only pid "$(lsappinfo front)" 2>/dev/null) || return 1
    [[ $info =~ 'pid = ([0-9]+)' ]] && print -r -- $match[1]
}

# L'app aperta si chiude anche se lo script si interrompe (Ctrl-C compreso) o se `pgrep` non l'ha
# trovata: `pkill` cerca il binario di questa build, mai l'app installata.
pid=""
trap 'pkill -f "$binary" 2>/dev/null; true' EXIT
trap 'exit 130' INT TERM

failed=0
for page in $pages; do
    for appearance in light dark; do
        # `open` avvia l'app da LaunchServices, come il Finder: un processo figlio di questa shell
        # potrebbe non ricevere finestre.
        # `-ApplePersistenceIgnoreState`: la finestra si apre alla misura predefinita, non a quella salvata.
        open -n "$bundle" --args -MJMDemo "$page" -MJMAppearance "$appearance" -ApplePersistenceIgnoreState YES
        # Il tempo per caricare la pagina e, per le Impostazioni, aprire lo sheet.
        sleep 3
        pid=$(pgrep -n -f "$binary" || true)
        if [[ -n $pid ]] && id=$("$build/window-id" "$pid" 10); then
            # Con il Mac in uso macOS non porta l'app davanti (attivazione cooperativa): la finestra
            # inattiva ha i pulsanti in tinta grigi e non vale come base del confronto.
            if [[ $(front_pid || true) != "$pid" ]]; then
                print -u2 "finestra non attiva per $page ($appearance): il Mac è in uso? nessuna cattura"
                failed=1
            elif screencapture -x -o -l"$id" "$out/$page-$appearance.png"; then
                print "$out/$page-$appearance.png"
            else
                print -u2 "cattura non riuscita per $page ($appearance): lo schermo è bloccato o spento?"
                failed=1
            fi
        else
            print -u2 "nessuna finestra per $page ($appearance)"
            failed=1
        fi
        pkill -f "$binary" 2>/dev/null || true
        pid=""
        sleep 1
    done
done
exit $failed
