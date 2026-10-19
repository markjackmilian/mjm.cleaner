#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
INSTALL_SCRIPT="$SCRIPT_DIR/../MjmCleanerKit/Sources/CleanerCore/Resources/update-install.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/private/tmp}/update-install-test.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$INSTALL_SCRIPT" ]] || fail "update-install.sh missing"

# Shim: `open` registra il percorso invece di aprire un'app; `mv` fallisce quando il primo
# argomento contiene FAIL_MV_MATCH. Tutto il resto viene dai comandi di sistema.
SHIMS="$TMP_ROOT/shims"
mkdir -p "$SHIMS"
cat > "$SHIMS/open" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >> "$OPENED"
SH
cat > "$SHIMS/mv" <<'SH'
#!/bin/sh
case "$1" in
  *"${FAIL_MV_MATCH:-<none>}"*) echo "mv: simulated failure" >&2; exit 1 ;;
esac
exec /bin/mv "$@"
SH
chmod +x "$SHIMS/open" "$SHIMS/mv"

# Un caso: cartella «Applications» con il bundle attuale, cartella updates con il nuovo bundle.
# Gli spazi e l'apostrofo nei percorsi verificano che nulla venga reinterpretato dalla shell.
setup() {
  CASE="$TMP_ROOT/$1/l'utente con spazi"
  APPS="$CASE/Applications"
  UPDATES="$CASE/updates"
  TARGET="$APPS/mjm.cleaner.app"
  SOURCE="$UPDATES/v0.2.0/expanded/mjm.cleaner.app"
  mkdir -p "$TARGET/Contents" "$SOURCE/Contents"
  printf 'vecchio\n' > "$TARGET/Contents/version"
  printf 'nuovo\n' > "$SOURCE/Contents/version"
  export OPENED="$CASE/opened"
  : > "$OPENED"
}

run_install() {
  PATH="$SHIMS:/usr/bin:/bin:/usr/sbin:/sbin" /bin/sh "$INSTALL_SCRIPT" "$1" "$TARGET" "$SOURCE" v0.2.0 "$UPDATES" "${2:-150}"
}

# Un PID sicuramente terminato: quello di un processo appena atteso.
dead_pid() {
  /usr/bin/true &
  local pid=$!
  wait "$pid"
  printf '%s' "$pid"
}

# Sostituzione riuscita, dopo che il processo atteso è terminato.
setup success
sleep 1 &
waiting=$!
run_install "$waiting"
kill -0 "$waiting" 2>/dev/null && fail "installed before the process exited"
[[ "$(cat "$TARGET/Contents/version")" == nuovo ]] || fail "bundle not replaced"
[[ "$(cat "$UPDATES/install-result")" == "ok v0.2.0" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ ! -e "$UPDATES/v0.2.0" ]] || fail "release directory left behind"
[[ -z "$(find "$APPS" -name '.mjm.cleaner-*' -maxdepth 1)" ]] || fail "staging or old bundle left behind"
[[ "$(cat "$OPENED")" == "$TARGET" ]] || fail "app not reopened at its path"
grep -q "aggiornamento a v0.2.0" "$UPDATES/install.log" || fail "log not written"
printf 'PASS: replace and reopen\n'

# La seconda rinomina fallisce: torna il bundle vecchio, che viene riaperto.
setup rollback
FAIL_MV_MATCH=".mjm.cleaner-update-" run_install "$(dead_pid)"
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "old bundle not restored"
[[ "$(cat "$UPDATES/install-result")" == "failed move-new" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ -z "$(find "$APPS" -name '.mjm.cleaner-*' -maxdepth 1)" ]] || fail "staging left behind after rollback"
[[ -d "$SOURCE" ]] || fail "verified bundle removed after a failed install"
[[ "$(cat "$OPENED")" == "$TARGET" ]] || fail "old app not reopened"
printf 'PASS: rollback\n'

# La prima rinomina fallisce: il bundle attuale non viene toccato.
setup move_old
FAIL_MV_MATCH="Applications/mjm.cleaner.app" run_install "$(dead_pid)"
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "current bundle touched"
[[ "$(cat "$UPDATES/install-result")" == "failed move-old" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ -z "$(find "$APPS" -name '.mjm.cleaner-*' -maxdepth 1)" ]] || fail "staging left behind"
printf 'PASS: current bundle kept\n'

# Il nuovo bundle non si copia: niente cambia.
setup copy
rm -rf "$SOURCE"
run_install "$(dead_pid)" || true
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "current bundle touched"
[[ "$(cat "$UPDATES/install-result")" == "failed copy" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
printf 'PASS: copy failure\n'

# Il processo non termina entro il limite: nessuna modifica e nessuna riapertura.
setup timeout
sleep 30 &
alive=$!
if run_install "$alive" 3; then fail "timeout reported success"; fi
kill "$alive"
wait "$alive" 2>/dev/null || true
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "bundle replaced while the app was running"
[[ "$(cat "$UPDATES/install-result")" == "failed wait" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ ! -s "$OPENED" ]] || fail "app reopened after a timeout"
printf 'PASS: wait timeout\n'
