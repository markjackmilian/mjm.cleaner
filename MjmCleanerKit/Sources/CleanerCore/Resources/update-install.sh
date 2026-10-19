#!/bin/sh
# Sostituisce il bundle di mjm.cleaner con quello verificato e riapre l'app (spec
# 2026-10-19-app-updates-design.md, «Installazione»). Lo avvia l'app un attimo prima di chiudersi,
# con PATH=/usr/bin:/bin:/usr/sbin:/sbin; i percorsi arrivano solo come argomenti.
#
#   update-install.sh PID BUNDLE_ATTUALE BUNDLE_NUOVO TAG CARTELLA_UPDATES PASSI_DI_ATTESA
#
# Esito in CARTELLA_UPDATES/install-result («ok TAG» o «failed PASSO»), log in install.log.
set -u
trap '' HUP

[ "$#" -eq 6 ] || exit 2
case "$4" in v[0-9]*.[0-9]*.[0-9]*) ;; *) exit 2 ;; esac
case "${4#v}" in *[!0-9.]*) exit 2 ;; esac
case "$1" in ''|*[!0-9]*) exit 2 ;; esac
case "$6" in ''|*[!0-9]*) exit 2 ;; esac

pid=$1
target=$2
source=$3
tag=$4
updates=$5
limit=$6

log="$updates/install.log"
result="$updates/install-result"
parent=$(dirname -- "$target")
staging="$parent/.mjm.cleaner-update-$tag.app"
old="$parent/.mjm.cleaner-old-$tag.app"

note() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$log"
}

# Scrive l'esito e riapre il bundle al percorso originale: il nuovo, o il vecchio dopo un ripristino.
finish() {
  printf '%s\n' "$1" >"$result"
  note "$1"
  open "$target" >>"$log" 2>&1 || note "riapertura non riuscita"
  exit 0
}

note "aggiornamento a $tag: attesa della fine del processo $pid"
steps=0
while kill -0 "$pid" 2>/dev/null; do
  steps=$((steps + 1))
  if [ "$steps" -ge "$limit" ]; then
    # L'app è ancora aperta: niente da toccare e niente da riaprire.
    printf 'failed wait\n' >"$result"
    note "il processo $pid non è terminato: aggiornamento annullato"
    exit 1
  fi
  sleep 0.2
done

# Mai sostituire una copia di appoggio (dopo un «failed rollback» l'unica copia sta lì) né un
# percorso che non esiste: `rm -rf "$old"` qui sotto cancellerebbe il bundle in uso.
case "$(basename -- "$target")" in .mjm.cleaner-update-*|.mjm.cleaner-old-*) finish "failed target" ;; esac
[ -d "$target" ] || finish "failed target"

rm -rf "$staging" "$old"
if [ -e "$staging" ] || [ -e "$old" ]; then finish "failed copy"; fi
if ! ditto "$source" "$staging" >>"$log" 2>&1; then
  rm -rf "$staging"
  finish "failed copy"
fi
if ! mv "$target" "$old" >>"$log" 2>&1; then
  rm -rf "$staging"
  finish "failed move-old"
fi
if ! mv "$staging" "$target" >>"$log" 2>&1; then
  if mv "$old" "$target" >>"$log" 2>&1; then
    rm -rf "$staging"
    finish "failed move-new"
  fi
  note "il bundle precedente è in $old"
  finish "failed rollback"
fi
rm -rf "$old" "$updates/$tag"
finish "ok $tag"
