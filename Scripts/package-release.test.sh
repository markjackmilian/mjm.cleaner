#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
PACKAGE_SCRIPT="$SCRIPT_DIR/package-release.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/private/tmp}/package-release-test.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Input validation must be available without invoking Xcode or creating output.
if [[ ! -x "$PACKAGE_SCRIPT" ]]; then
  fail "package-release.sh missing or not executable"
fi
[[ "$("$PACKAGE_SCRIPT" --tag v0.1.0 --build-number 1 --validate-only)" == "0.1.0" ]] || fail "valid input did not print normalized version"
for args in \
  '--tag v1 --build-number 1 --validate-only' \
  '--tag v1.2.3-rc1 --build-number 1 --validate-only' \
  '--tag v1.2.3 --build-number 0 --validate-only' \
  '--tag v1.2.3 --build-number abc --validate-only' \
  '--tag v1.2.3 --validate-only --unknown'; do
  if "$PACKAGE_SCRIPT" $args >"$TMP_ROOT/stdout" 2>"$TMP_ROOT/stderr"; then
    fail "invalid arguments unexpectedly accepted: $args"
  fi
done
"$PACKAGE_SCRIPT" --tag v1.2.3 --build-number 1 --validate-only --output-dir "$TMP_ROOT/validate-output" >/dev/null
[[ ! -e "$TMP_ROOT/validate-output" ]] || fail "validate-only created output directory"

printf 'PASS: input validation\n'

# Tool shims create a minimal app and let each packaging failure be injected.
SHIMS="$TMP_ROOT/shims"
mkdir -p "$SHIMS"
cat > "$SHIMS/xcodebuild" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ -z "${RACE_SECOND_BUILD:-}" ]] || : > "$RACE_SECOND_BUILD"
case "${RACE_CREATE_ZIP_KIND:-}" in
  symlink) ln -s /dev/null "$RACE_ZIP_PATH" ;;
  fifo) mkfifo "$RACE_ZIP_PATH" ;;
  directory) mkdir "$RACE_ZIP_PATH"; printf 'preserve me\n' > "$RACE_ZIP_PATH/sentinel" ;;
  symlink_directory)
    mkdir "$RACE_ZIP_TARGET"
    printf 'preserve me\n' > "$RACE_ZIP_TARGET/sentinel"
    ln -s "$RACE_ZIP_TARGET" "$RACE_ZIP_PATH"
    ;;
esac
if [[ "${FAIL_STAGE:-}" == build ]]; then exit 31; fi
if [[ -n "${RACE_STARTED:-}" ]]; then
  : > "$RACE_STARTED"
  while [[ ! -e "$RACE_RELEASE" ]]; do sleep 0.05; done
fi
while (($#)); do
  if [[ "$1" == -derivedDataPath ]]; then DERIVED=$2; break; fi
  shift
done
APP="$DERIVED/Build/Products/Release/MjmCleaner.app"
mkdir -p "$APP/Contents/MacOS"
printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/MjmCleaner"
chmod +x "$APP/Contents/MacOS/MjmCleaner"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.mjm.cleaner</string>
<key>CFBundleName</key><string>mjm.cleaner</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST
SH
cat > "$SHIMS/lipo" <<'SH'
#!/usr/bin/env bash
[[ "${FAIL_STAGE:-}" != verify ]] || exit 32
printf 'x86_64 arm64\n'
SH
cat > "$SHIMS/codesign" <<'SH'
#!/usr/bin/env bash
if [[ "${FAIL_STAGE:-}" == verify ]]; then exit 33; fi
if [[ "$1" == -dv ]]; then printf 'Identifier=com.mjm.cleaner\nSignature=adhoc\n' >&2; fi
SH
cat > "$SHIMS/ditto" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == -c ]]; then
  [[ "${FAIL_STAGE:-}" != compress ]] || exit 34
  while (($# > 2)); do shift; done
  src=$1; dst=$2
  mkdir -p "$dst"
  cp -R "$src" "$dst/"
elif [[ "$1" == -x ]]; then
  [[ "${FAIL_STAGE:-}" != extract ]] || exit 35
  src=$3; dst=$4
  mkdir -p "$dst"
  cp -R "$src/." "$dst/"
else
  [[ "${FAIL_STAGE:-}" != transfer_bundle ]] || exit 36
  cp -R "$1/." "$2/"
fi
SH
cat > "$SHIMS/cat" <<'SH'
#!/usr/bin/env bash
if [[ "${FAIL_STAGE:-}" == transfer_zip ]]; then
  printf 'partial zip'
  exit 37
fi
if [[ -d "$1" ]]; then printf 'mock archive\n'; else exec /bin/cat "$@"; fi
SH
chmod +x "$SHIMS"/*

make_env() {
  local stage=$1 out=$2
  mkdir -p "$out/unrelated"
  printf 'preserve me\n' > "$out/unrelated/sentinel"
  if FAIL_STAGE="$stage" PATH="$SHIMS:$PATH" "$PACKAGE_SCRIPT" --tag v0.1.0 --build-number 1 --output-dir "$out" >"$TMP_ROOT/$stage.stdout" 2>"$TMP_ROOT/$stage.stderr"; then
    fail "$stage failure injection unexpectedly succeeded"
  fi
  [[ "$(cat "$out/unrelated/sentinel")" == 'preserve me' ]] || fail "$stage failure changed unrelated sentinel"
  [[ ! -e "$out/mjm.cleaner.app" ]] || fail "$stage failure left a partial app"
  [[ ! -e "$out/mjm.cleaner-v0.1.0-macos-universal.zip" ]] || fail "$stage failure left a partial ZIP"
}

# Existing destination artifacts must be rejected byte-for-byte intact.
BUNDLE_COLLISION="$TMP_ROOT/bundle-collision"
mkdir -p "$BUNDLE_COLLISION/mjm.cleaner.app"
printf 'bundle sentinel\n' > "$BUNDLE_COLLISION/mjm.cleaner.app/sentinel"
cp "$BUNDLE_COLLISION/mjm.cleaner.app/sentinel" "$TMP_ROOT/bundle.sentinel"
if "$PACKAGE_SCRIPT" --tag v0.1.0 --build-number 1 --output-dir "$BUNDLE_COLLISION" >/dev/null 2>&1; then fail "existing bundle was overwritten"; fi
cmp -s "$BUNDLE_COLLISION/mjm.cleaner.app/sentinel" "$TMP_ROOT/bundle.sentinel" || fail "bundle collision changed sentinel"
ZIP_COLLISION="$TMP_ROOT/zip-collision"
mkdir -p "$ZIP_COLLISION"
printf 'zip sentinel\n' > "$ZIP_COLLISION/mjm.cleaner-v0.1.0-macos-universal.zip"
cp "$ZIP_COLLISION/mjm.cleaner-v0.1.0-macos-universal.zip" "$TMP_ROOT/zip.sentinel"
if "$PACKAGE_SCRIPT" --tag v0.1.0 --build-number 1 --output-dir "$ZIP_COLLISION" >/dev/null 2>&1; then fail "existing ZIP was overwritten"; fi
cmp -s "$ZIP_COLLISION/mjm.cleaner-v0.1.0-macos-universal.zip" "$TMP_ROOT/zip.sentinel" || fail "ZIP collision changed sentinel"

for stage in build verify compress transfer_bundle transfer_zip; do
  make_env "$stage" "$TMP_ROOT/$stage-output"
done

# A symlink or FIFO at the final ZIP name is an existing object. Reject it
# promptly before xcodebuild; never follow, truncate, or unlink it.
check_special_zip_collision() {
  local kind=$1 out="$TMP_ROOT/special-$1" zip="$TMP_ROOT/special-$1/mjm.cleaner-v0.1.0-macos-universal.zip"
  local marker="$TMP_ROOT/special-$1-build-started" pid status=124
  mkdir -p "$out"
  if [[ "$kind" == symlink ]]; then ln -s /dev/null "$zip"; else mkfifo "$zip"; fi
  FAIL_STAGE=build RACE_SECOND_BUILD="$marker" PATH="$SHIMS:$PATH" \
    "$PACKAGE_SCRIPT" --tag v0.1.0 --build-number 1 --output-dir "$out" >"$TMP_ROOT/special-$kind.log" 2>&1 &
  pid=$!
  for _ in {1..40}; do
    if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" || status=$?; break; fi
    sleep 0.05
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    fail "$kind ZIP collision blocked instead of rejecting promptly"
  fi
  [[ "$status" -ne 0 ]] || fail "$kind ZIP collision unexpectedly succeeded"
  [[ ! -e "$marker" ]] || fail "$kind ZIP collision reached xcodebuild"
  if [[ "$kind" == symlink ]]; then
    [[ -L "$zip" && "$(readlink "$zip")" == /dev/null ]] || fail "preexisting ZIP symlink was changed or removed"
  else
    [[ -p "$zip" ]] || fail "preexisting ZIP FIFO was changed or removed"
  fi
  [[ ! -e "$out/mjm.cleaner.app" ]] || fail "$kind ZIP collision left a reserved bundle"
}
check_special_zip_collision symlink
check_special_zip_collision fifo

# If another process claims the ZIP pathname after our build has started, a
# failed build must preserve that object while cleaning our reserved bundle.
check_build_failure_preserves_special_zip() {
  local kind=$1 out="$TMP_ROOT/build-failure-$1" zip="$TMP_ROOT/build-failure-$1/mjm.cleaner-v0.1.0-macos-universal.zip"
  local marker="$TMP_ROOT/build-failure-$1-started"
  mkdir -p "$out"
  if FAIL_STAGE=build RACE_SECOND_BUILD="$marker" RACE_CREATE_ZIP_KIND="$kind" RACE_ZIP_PATH="$zip" PATH="$SHIMS:$PATH" \
    "$PACKAGE_SCRIPT" --tag v0.1.0 --build-number 1 --output-dir "$out" >"$TMP_ROOT/build-failure-$kind.log" 2>&1; then
    fail "$kind ZIP object injected during failed build unexpectedly succeeded"
  fi
  [[ -e "$marker" ]] || fail "build failure injection did not reach xcodebuild"
  if [[ "$kind" == symlink ]]; then
    [[ -L "$zip" && "$(readlink "$zip")" == /dev/null ]] || fail "build cleanup removed or changed racing ZIP symlink"
  else
    [[ -p "$zip" ]] || fail "build cleanup removed or changed racing ZIP FIFO"
  fi
  [[ ! -e "$out/mjm.cleaner.app" ]] || fail "build failure left reserved bundle"
}
check_build_failure_preserves_special_zip symlink
check_build_failure_preserves_special_zip fifo

# A directory or symlink to a directory that appears during build must not be
# treated by ln as a container for the ZIP hard link.
check_build_success_rejects_directory_claim() {
  local kind=$1 out="$TMP_ROOT/build-success-$1" zip="$TMP_ROOT/build-success-$1/mjm.cleaner-v0.1.0-macos-universal.zip"
  local target="$TMP_ROOT/build-success-$1-target" marker="$TMP_ROOT/build-success-$1-started"
  mkdir -p "$out"
  if RACE_SECOND_BUILD="$marker" RACE_CREATE_ZIP_KIND="$kind" RACE_ZIP_PATH="$zip" RACE_ZIP_TARGET="$target" PATH="$SHIMS:$PATH" \
    "$PACKAGE_SCRIPT" --tag v0.1.0 --build-number 1 --output-dir "$out" >"$TMP_ROOT/build-success-$kind.log" 2>&1; then
    fail "$kind created during build was accepted as ZIP output"
  fi
  [[ -e "$marker" ]] || fail "directory race test did not reach xcodebuild"
  if [[ "$kind" == directory ]]; then
    [[ -d "$zip" && ! -L "$zip" ]] || fail "racing ZIP directory changed"
    [[ "$(/bin/cat "$zip/sentinel")" == 'preserve me' ]] || fail "racing ZIP directory sentinel changed"
    [[ "$(find "$zip" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" == 1 ]] || fail "ZIP link was created inside racing directory"
  else
    [[ -L "$zip" && "$(readlink "$zip")" == "$target" ]] || fail "racing directory symlink changed"
    [[ "$(/bin/cat "$target/sentinel")" == 'preserve me' ]] || fail "racing symlink target sentinel changed"
    [[ "$(find "$target" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" == 1 ]] || fail "ZIP link was created inside racing symlink target"
  fi
  [[ ! -e "$out/mjm.cleaner.app" ]] || fail "failed directory race left reserved bundle"
}
check_build_success_rejects_directory_claim directory
check_build_success_rejects_directory_claim symlink_directory

# A second package process must fail while the first owns its output names.
RACE_OUT="$TMP_ROOT/race-output"
RACE_STARTED="$TMP_ROOT/race-started"
RACE_RELEASE="$TMP_ROOT/race-release"
RACE_LOG="$TMP_ROOT/race-first.log"
RACE_STARTED="$RACE_STARTED" RACE_RELEASE="$RACE_RELEASE" PATH="$SHIMS:$PATH" \
  "$PACKAGE_SCRIPT" --tag v0.1.0 --build-number 1 --output-dir "$RACE_OUT" >"$RACE_LOG" 2>&1 &
RACE_PID=$!
for _ in {1..200}; do [[ -e "$RACE_STARTED" ]] && break; sleep 0.05; done
[[ -e "$RACE_STARTED" ]] || fail "first packaging process did not reach build gate"
if RACE_SECOND_BUILD="$TMP_ROOT/race-second-build" PATH="$SHIMS:$PATH" \
  "$PACKAGE_SCRIPT" --tag v0.1.0 --build-number 1 --output-dir "$RACE_OUT" >"$TMP_ROOT/race-second.log" 2>&1; then
  : > "$RACE_RELEASE"
  wait "$RACE_PID" || true
  fail "concurrent packaging process acquired already-reserved outputs"
fi
grep -E -q 'Refusing to (overwrite|reserve)' "$TMP_ROOT/race-second.log" || fail "concurrent process did not fail at output reservation"
[[ ! -e "$TMP_ROOT/race-second-build" ]] || fail "concurrent process started xcodebuild"
[[ ! -e "$RACE_OUT/mjm.cleaner.app/Contents/MacOS/MjmCleaner" ]] || fail "concurrent invocation created an app inside the reservation"
: > "$RACE_RELEASE"
wait "$RACE_PID" || { cat "$RACE_LOG" >&2; fail "reservation owner failed after releasing build gate"; }
[[ -x "$RACE_OUT/mjm.cleaner.app/Contents/MacOS/MjmCleaner" ]] || fail "reservation owner did not complete app"

printf 'PASS: collision refusal and failure cleanup\n'
