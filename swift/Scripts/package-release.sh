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
work=$(mktemp -d "${TMPDIR:-/private/tmp}/mjm-cleaner-release.XXXXXX")
bundle_identity=''
zip_identity=''
object_identity() {
  stat -f '%d:%i' "$1" 2>/dev/null
}
cleanup() {
  status=$?
  if ((status != 0)); then
    if [[ -n "$zip_identity" && -e "$zip_dest" && "$(object_identity "$zip_dest")" == "$zip_identity" ]]; then
      rm -f -- "$zip_dest"
    fi
    if [[ -n "$bundle_identity" && -d "$bundle_dest" && "$(object_identity "$bundle_dest")" == "$bundle_identity" ]]; then
      rm -rf -- "$bundle_dest"
    fi
  fi
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT

# Claim each final name atomically before building. Competing package runs fail
# on mkdir or noclobber, and cleanup removes only the inodes claimed here.
if ! mkdir -- "$bundle_dest"; then
  printf 'Refusing to overwrite or claim %s\n' "$bundle_dest" >&2
  exit 1
fi
bundle_identity=$(object_identity "$bundle_dest")
if ! (set -o noclobber; : > "$zip_dest"); then
  printf 'Refusing to overwrite or claim %s\n' "$zip_dest" >&2
  exit 1
fi
zip_identity=$(object_identity "$zip_dest")

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
}

check_bundle "$built_app"
ditto "$built_app" "$bundle_dest"
check_bundle "$bundle_dest"
ditto -c -k --sequesterRsrc --keepParent "$bundle_dest" "$work/$zip_name"
mkdir "$work/extracted"
ditto -x -k "$work/$zip_name" "$work/extracted"
check_bundle "$work/extracted/$bundle_name"
[[ "$(object_identity "$bundle_dest")" == "$bundle_identity" ]] || { printf 'Reserved bundle path changed during packaging\n' >&2; exit 1; }
[[ "$(object_identity "$zip_dest")" == "$zip_identity" ]] || { printf 'Reserved ZIP path changed during packaging\n' >&2; exit 1; }
cat "$work/$zip_name" > "$zip_dest"
printf 'Packaged %s and %s\n' "$bundle_dest" "$zip_dest"
