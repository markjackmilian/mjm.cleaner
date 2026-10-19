#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
INSTALL_SCRIPT="$SCRIPT_DIR/../MjmCleanerKit/Sources/CleanerCore/Resources/update-install.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/private/tmp}/update-install-test.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$INSTALL_SCRIPT" ]] || fail "update-install.sh missing"

# Shim: `open` registra percorso e esito scritto fino a quel momento; `mv` registra ogni
# chiamata e fallisce quando il primo argomento contiene FAIL_MV_MATCH; `ditto` con
# FAIL_DITTO=1 lascia una copia parziale e fallisce. Tutto il resto viene dai comandi di sistema.
SHIMS="$TMP_ROOT/shims"
mkdir -p "$SHIMS"
cat > "$SHIMS/open" <<'SH'
#!/bin/sh
printf '%s|%s\n' "$1" "$(cat "$RESULT" 2>/dev/null)" >> "$OPENED"
SH
cat > "$SHIMS/mv" <<'SH'
#!/bin/sh
printf '%s -> %s\n' "$1" "$2" >> "$MV_CALLS"
case "$1" in
  *"${FAIL_MV_MATCH:-<none>}"*) echo "mv: simulated failure" >&2; exit 1 ;;
esac
exec /bin/mv "$@"
SH
cat > "$SHIMS/ditto" <<'SH'
#!/bin/sh
if [ "${FAIL_DITTO:-0}" = 1 ]; then
  mkdir -p "$2/Contents"
  : > "$2/Contents/partial"
  echo "ditto: simulated failure" >&2
  exit 1
fi
exec /usr/bin/ditto "$@"
SH
chmod +x "$SHIMS/open" "$SHIMS/mv" "$SHIMS/ditto"

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
  export RESULT="$UPDATES/install-result"
  export MV_CALLS="$CASE/mv-calls"
  : > "$OPENED"
  : > "$MV_CALLS"
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
[[ "$(cat "$OPENED")" == "$TARGET|ok v0.2.0" ]] || fail "app not reopened at its path after the result: $(cat "$OPENED")"
expected_mv="$TARGET -> $APPS/.mjm.cleaner-old-v0.2.0.app
$APPS/.mjm.cleaner-update-v0.2.0.app -> $TARGET"
[[ "$(cat "$MV_CALLS")" == "$expected_mv" ]] || fail "unexpected mv calls: $(cat "$MV_CALLS")"
grep -q "aggiornamento a v0.2.0" "$UPDATES/install.log" || fail "log not written"
grep -q "ok v0.2.0" "$UPDATES/install.log" || fail "log without the final result"
printf 'PASS: replace and reopen\n'

# La seconda rinomina fallisce: torna il bundle vecchio, che viene riaperto.
setup rollback
FAIL_MV_MATCH=".mjm.cleaner-update-" run_install "$(dead_pid)"
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "old bundle not restored"
[[ "$(cat "$UPDATES/install-result")" == "failed move-new" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ -z "$(find "$APPS" -name '.mjm.cleaner-*' -maxdepth 1)" ]] || fail "staging left behind after rollback"
[[ -d "$SOURCE" ]] || fail "verified bundle removed after a failed install"
[[ "$(cat "$OPENED")" == "$TARGET|failed move-new" ]] || fail "old app not reopened with the result: $(cat "$OPENED")"
printf 'PASS: rollback\n'

# La prima rinomina fallisce: il bundle attuale non viene toccato.
setup move_old
FAIL_MV_MATCH="Applications/mjm.cleaner.app" run_install "$(dead_pid)"
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "current bundle touched"
[[ "$(cat "$UPDATES/install-result")" == "failed move-old" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ -z "$(find "$APPS" -name '.mjm.cleaner-*' -maxdepth 1)" ]] || fail "staging left behind"
[[ -d "$SOURCE" ]] || fail "verified bundle removed after a failed move-old"
printf 'PASS: current bundle kept\n'

# La copia del nuovo bundle fallisce e lascia una copia parziale: niente cambia.
setup copy
FAIL_DITTO=1 run_install "$(dead_pid)" || true
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "current bundle touched"
[[ "$(cat "$UPDATES/install-result")" == "failed copy" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ -z "$(find "$APPS" -name '.mjm.cleaner-*' -maxdepth 1)" ]] || fail "partial copy left behind"
[[ -d "$SOURCE" ]] || fail "verified bundle removed after a failed copy"
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

# Anche il rollback fallisce: resta il bundle vecchio, nella cartella di appoggio, e il verificato.
setup rollback_failed
FAIL_MV_MATCH=".mjm.cleaner-" run_install "$(dead_pid)"
[[ "$(cat "$UPDATES/install-result")" == "failed rollback" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ "$(cat "$APPS/.mjm.cleaner-old-v0.2.0.app/Contents/version")" == vecchio ]] || fail "old bundle not kept after a failed rollback"
[[ -d "$SOURCE" ]] || fail "verified bundle removed after a failed rollback"
grep -q "il bundle precedente è in" "$UPDATES/install.log" || fail "log without the location of the old bundle"
printf 'PASS: rollback failure keeps the old bundle\n'

# Il bundle da aggiornare è la copia nascosta lasciata da un rollback fallito: non si tocca.
setup hidden_target
HIDDEN="$APPS/.mjm.cleaner-old-v0.2.0.app"
/bin/mv "$TARGET" "$HIDDEN"
TARGET="$HIDDEN"
run_install "$(dead_pid)"
[[ "$(cat "$UPDATES/install-result")" == "failed target" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ "$(cat "$HIDDEN/Contents/version")" == vecchio ]] || fail "hidden copy touched"
[[ "$(ls -A "$APPS")" == ".mjm.cleaner-old-v0.2.0.app" ]] || fail "other files created next to the hidden copy: $(ls -A "$APPS")"
[[ -d "$SOURCE" ]] || fail "verified bundle removed after failed target"
[[ ! -s "$MV_CALLS" ]] || fail "something was moved: $(cat "$MV_CALLS")"
[[ "$(cat "$OPENED")" == "$HIDDEN|failed target" ]] || fail "hidden copy not reopened with the result: $(cat "$OPENED")"
printf 'PASS: hidden copy never swapped\n'

# Il bundle da aggiornare non esiste: niente da sostituire.
setup missing_target
rm -rf "$TARGET"
run_install "$(dead_pid)"
[[ "$(cat "$UPDATES/install-result")" == "failed target" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ -z "$(ls -A "$APPS")" ]] || fail "files created for a missing target: $(ls -A "$APPS")"
[[ -d "$SOURCE" ]] || fail "verified bundle removed after failed target"
printf 'PASS: missing target\n'

# Residui di un tentativo precedente: vengono rimossi prima di installare.
setup leftovers
mkdir -p "$APPS/.mjm.cleaner-update-v0.2.0.app/Contents"
: > "$APPS/.mjm.cleaner-update-v0.2.0.app/Contents/stray"
mkdir -p "$APPS/.mjm.cleaner-old-v0.2.0.app/Contents"
printf 'residuo\n' > "$APPS/.mjm.cleaner-old-v0.2.0.app/Contents/version"
run_install "$(dead_pid)"
[[ "$(cat "$UPDATES/install-result")" == "ok v0.2.0" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ "$(cat "$TARGET/Contents/version")" == nuovo ]] || fail "bundle not replaced over leftovers"
[[ ! -e "$TARGET/Contents/stray" ]] || fail "staging leftover reached the installed bundle"
[[ -z "$(find "$APPS" -name '.mjm.cleaner-*' -maxdepth 1)" ]] || fail "leftovers not cleared"
printf 'PASS: leftovers cleared\n'

# Un HUP inviato durante l'attesa (chiusura del terminale) non interrompe l'installazione.
setup hangup
sleep 1 &
waiting=$!
PATH="$SHIMS:/usr/bin:/bin:/usr/sbin:/sbin" /bin/sh "$INSTALL_SCRIPT" "$waiting" "$TARGET" "$SOURCE" v0.2.0 "$UPDATES" 150 &
script_pid=$!
sleep 0.3
kill -HUP "$script_pid"
wait "$script_pid" || true
wait "$waiting" 2>/dev/null || true
[[ "$(cat "$UPDATES/install-result")" == "ok v0.2.0" ]] || fail "hangup stopped the install: $(cat "$UPDATES/install-result" 2>/dev/null)"
[[ "$(cat "$TARGET/Contents/version")" == nuovo ]] || fail "bundle not replaced after hangup"
printf 'PASS: hangup ignored\n'

# Argomenti non validi: uscita 2, nessun esito scritto, nessuna modifica.
setup arguments
pid=$(dead_pid)
expect_rejected() {
  local rc=0
  PATH="$SHIMS:/usr/bin:/bin:/usr/sbin:/sbin" /bin/sh "$INSTALL_SCRIPT" "$@" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || fail "arguments accepted (exit $rc): $*"
  [[ ! -e "$UPDATES/install-result" ]] || fail "result written for rejected arguments: $*"
  [[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "current bundle touched for rejected arguments: $*"
  [[ ! -s "$OPENED" ]] || fail "app reopened for rejected arguments: $*"
}
expect_rejected "$pid" "$TARGET" "$SOURCE" v0.2.0 "$UPDATES"
expect_rejected "$pid" "$TARGET" "$SOURCE" "" "$UPDATES" 150
expect_rejected "$pid" "$TARGET" "$SOURCE" latest "$UPDATES" 150
expect_rejected abc "$TARGET" "$SOURCE" v0.2.0 "$UPDATES" 150
expect_rejected "$pid" "$TARGET" "$SOURCE" v0.2.0 "$UPDATES" x
expect_rejected "$pid" "$TARGET" "$SOURCE" "v1/../../x.0.0" "$UPDATES" 150
expect_rejected "$pid" "$TARGET" "$SOURCE" "v1.2.3 x" "$UPDATES" 150
expect_rejected "$pid" "$TARGET" "$SOURCE" v0.2.0 "$UPDATES" 150 extra
printf 'PASS: invalid arguments rejected\n'
