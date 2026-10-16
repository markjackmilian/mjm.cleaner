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
"$PACKAGE_SCRIPT" --tag v1.2.3 --build-number 1 --validate-only >/dev/null
[[ ! -e "$TMP_ROOT/validate-output" ]] || fail "validate-only created output directory"

printf 'PASS: input validation\n'

# Tool shims create a minimal app and let each packaging failure be injected.
SHIMS="$TMP_ROOT/shims"
mkdir -p "$SHIMS"
cat > "$SHIMS/xcodebuild" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${FAIL_STAGE:-}" != build ]] || exit 31
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
  mkdir -p "$(dirname "$dst")"
  cp -R "$src" "$dst"
else
  [[ "$1" == -x && "${FAIL_STAGE:-}" != extract ]] || exit 35
  src=$3; dst=$4
  mkdir -p "$dst"
  cp -R "$src" "$dst/"
fi
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

for stage in build verify compress; do
  make_env "$stage" "$TMP_ROOT/$stage-output"
done

printf 'PASS: collision refusal and failure cleanup\n'
