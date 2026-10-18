#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: package-release.sh --tag vX.Y.Z --build-number N [--output-dir DIR] [--validate-only]
USAGE
}

tag=''
build_number=''
output_dir=''
validate_only=0
while (($#)); do
  case "$1" in
    --tag|--build-number|--output-dir)
      option=$1
      (($# >= 2)) || { printf 'Missing value for %s\n' "$option" >&2; usage; exit 2; }
      case "$option" in
        --tag) tag=$2 ;;
        --build-number) build_number=$2 ;;
        --output-dir) output_dir=$2 ;;
      esac
      shift 2
      ;;
    --validate-only)
      ((validate_only == 0)) || { printf 'Duplicate --validate-only\n' >&2; exit 2; }
      validate_only=1
      shift
      ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'Invalid tag: %s\n' "$tag" >&2; exit 2; }
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || { printf 'Invalid build number: %s\n' "$build_number" >&2; exit 2; }
version=${tag#v}
printf '%s\n' "$version"
if ((validate_only)); then
  exit 0
fi
[[ -n "$output_dir" ]] || { printf '--output-dir is required for packaging\n' >&2; usage; exit 2; }

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
output_dir=$(mkdir -p -- "$output_dir" && cd -- "$output_dir" && pwd)
bundle_name='mjm.cleaner.app'
zip_name="mjm.cleaner-${tag}-macos-universal.zip"
bundle_dest="$output_dir/$bundle_name"
zip_dest="$output_dir/$zip_name"
zip_lock="$output_dir/.${zip_name}.lock"
[[ ! -e "$bundle_dest" && ! -L "$bundle_dest" ]] || { printf 'Refusing to overwrite %s\n' "$bundle_dest" >&2; exit 1; }
[[ ! -e "$zip_dest" && ! -L "$zip_dest" ]] || { printf 'Refusing to overwrite %s\n' "$zip_dest" >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/private/tmp}/mjm-cleaner-release.XXXXXX")
bundle_identity=''
zip_lock_identity=''
zip_stage=''
zip_stage_identity=''
zip_identity=''
object_identity() {
  stat -f '%d:%i' "$1" 2>/dev/null
}
cleanup() {
  status=$?
  if ((status != 0)); then
    if [[ -n "$zip_identity" && -f "$zip_dest" && ! -L "$zip_dest" && "$(object_identity "$zip_dest")" == "$zip_identity" ]]; then
      rm -f -- "$zip_dest"
    fi
    if [[ -n "$bundle_identity" && -d "$bundle_dest" && ! -L "$bundle_dest" && "$(object_identity "$bundle_dest")" == "$bundle_identity" ]]; then
      rm -rf -- "$bundle_dest"
    fi
  fi
  if [[ -n "$zip_stage_identity" && -e "$zip_stage" && "$(object_identity "$zip_stage")" == "$zip_stage_identity" ]]; then
    rm -f -- "$zip_stage"
  fi
  if [[ -n "$zip_lock_identity" && -d "$zip_lock" && "$(object_identity "$zip_lock")" == "$zip_lock_identity" ]]; then
    rm -rf -- "$zip_lock"
  fi
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT

# Reserve the bundle name and a private ZIP lock before building. The ZIP itself
# is published later with link(2), which atomically refuses every existing object.
if ! mkdir -- "$bundle_dest"; then
  printf 'Refusing to overwrite or claim %s\n' "$bundle_dest" >&2
  exit 1
fi
bundle_identity=$(object_identity "$bundle_dest")
if ! mkdir -- "$zip_lock"; then
  printf 'Refusing to reserve %s\n' "$zip_dest" >&2
  exit 1
fi
zip_lock_identity=$(object_identity "$zip_lock")
zip_stage=$(mktemp "$output_dir/.${zip_name}.stage.XXXXXX")
zip_stage_identity=$(object_identity "$zip_stage")

xcodebuild -project "$PROJECT_ROOT/MjmCleaner.xcodeproj" -scheme MjmCleaner -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$work/DerivedData" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" build

built_app="$work/DerivedData/Build/Products/Release/MjmCleaner.app"
[[ -d "$built_app" ]] || { printf 'Build did not produce %s\n' "$built_app" >&2; exit 1; }

check_bundle() {
  local app=$1 executable="$1/Contents/MacOS/MjmCleaner" plist="$1/Contents/Info.plist" archs
  [[ -x "$executable" && -f "$plist" ]] || { printf 'Invalid app bundle: %s\n' "$app" >&2; return 1; }
  archs=$(lipo -archs "$executable")
  [[ " $(printf '%s\n' "$archs" | tr ' ' '\n' | sort -u | tr '\n' ' ')" == ' arm64 x86_64 ' ]] || { printf 'Expected arm64 and x86_64, got: %s\n' "$archs" >&2; return 1; }
  local key expected
  for key_expected in \
    'CFBundleIdentifier=com.mjm.cleaner' \
    'CFBundleName=mjm.cleaner' \
    "CFBundleShortVersionString=$version" \
    "CFBundleVersion=$build_number" \
    'LSMinimumSystemVersion=15.0'; do
    key=${key_expected%%=*}; expected=${key_expected#*=}
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")" == "$expected" ]] || { printf 'Unexpected %s in %s\n' "$key" "$plist" >&2; return 1; }
  done
  codesign --verify --deep --strict "$app"
  codesign -dv --verbose=4 "$app" 2>"$work/codesign.txt"
  grep -q '^Signature=adhoc$' "$work/codesign.txt" || { printf 'Expected ad hoc signature\n' >&2; return 1; }
  if grep -R -a -E -q 'MJMDemo|Pagina demo' "$app/Contents/MacOS"; then
    printf 'Release binary contains demo content\n' >&2; return 1
  fi
  check_no_local_paths "$app"
}

# Il pacchetto non deve nominare la macchina che lo ha costruito. Senza strip, il binario porta la
# mappa di debug (voci SO/OSO di `nm -ap`) con la cartella temporanea di questo script, la
# DerivedData e il checkout: percorsi diversi a ogni build. Config/Release.xcconfig li toglie con
# `strip -D -S`; qui si verifica il risultato su ogni copia del bundle, ZIP estratto compreso.
# L'app nomina «/Users» di proposito (PathGuard): si cerca il percorso di una home,
# `/Users/<nome>/`, non il prefisso da solo. Un futuro letterale legittimo come `/Users/Shared/…`
# farebbe fallire il pacchetto (oggi non ce ne sono). Il percorso del checkout si cerca a parte:
# fuori da /Users (/Volumes, /opt su un runner self-hosted) il modello della home non lo vede.
check_no_local_paths() {
  local app=$1 scan hit status
  for scan in generic checkout; do
    status=0
    # grep esce con 0 se trova una corrispondenza, 1 se non ne trova, altro se la scansione fallisce.
    case $scan in
      generic) hit=$(LC_ALL=C grep -R -a -l -E '/var/folders/|mjm-cleaner-release|/Users/[A-Za-z0-9._-]+/' "$app/Contents") || status=$? ;;
      checkout) hit=$(LC_ALL=C grep -R -a -l -F -e "$PROJECT_ROOT/" "$app/Contents") || status=$? ;;
    esac
    case $status in
      0) printf 'Release bundle contains a local build path: %s\n' "${hit%%$'\n'*}" >&2; return 1 ;;
      1) ;;
      *) printf 'Cannot scan %s for local build paths\n' "$app" >&2; return 1 ;;
    esac
  done
}

check_bundle "$built_app"
ditto "$built_app" "$bundle_dest"
check_bundle "$bundle_dest"
ditto -c -k --sequesterRsrc --keepParent "$bundle_dest" "$work/$zip_name"
mkdir "$work/extracted"
ditto -x -k "$work/$zip_name" "$work/extracted"
check_bundle "$work/extracted/$bundle_name"
[[ "$(object_identity "$bundle_dest")" == "$bundle_identity" ]] || { printf 'Reserved bundle path changed during packaging\n' >&2; exit 1; }
[[ "$(object_identity "$zip_lock")" == "$zip_lock_identity" ]] || { printf 'ZIP reservation changed during packaging\n' >&2; exit 1; }
[[ "$(object_identity "$zip_stage")" == "$zip_stage_identity" ]] || { printf 'ZIP staging file changed during packaging\n' >&2; exit 1; }
cat "$work/$zip_name" > "$zip_stage"
/bin/link "$zip_stage" "$zip_dest"
zip_identity=$zip_stage_identity
printf 'Packaged %s and %s\n' "$bundle_dest" "$zip_dest"
