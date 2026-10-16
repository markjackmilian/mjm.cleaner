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
[[ ! -e "$bundle_dest" && ! -L "$bundle_dest" ]] || { printf 'Refusing to overwrite %s\n' "$bundle_dest" >&2; exit 1; }
[[ ! -e "$zip_dest" && ! -L "$zip_dest" ]] || { printf 'Refusing to overwrite %s\n' "$zip_dest" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/private/tmp}/mjm-cleaner-release.XXXXXX")
created_bundle=0
created_zip=0
cleanup() {
  status=$?
  if ((status != 0)); then
    ((created_zip == 0)) || rm -f -- "$zip_dest"
    ((created_bundle == 0)) || rm -rf -- "$bundle_dest"
  fi
  rm -rf -- "$work"
  exit "$status"
}
trap cleanup EXIT

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
cp -R -- "$built_app" "$work/$bundle_name"
check_bundle "$work/$bundle_name"
ditto -c -k --sequesterRsrc --keepParent "$work/$bundle_name" "$work/$zip_name"
mkdir "$work/extracted"
ditto -x -k "$work/$zip_name" "$work/extracted"
check_bundle "$work/extracted/$bundle_name"

# Refuse a destination race as well as collisions found before the build.
[[ ! -e "$bundle_dest" && ! -L "$bundle_dest" ]] || { printf 'Refusing to overwrite %s\n' "$bundle_dest" >&2; exit 1; }
[[ ! -e "$zip_dest" && ! -L "$zip_dest" ]] || { printf 'Refusing to overwrite %s\n' "$zip_dest" >&2; exit 1; }
mv -- "$work/$bundle_name" "$bundle_dest"
created_bundle=1
mv -- "$work/$zip_name" "$zip_dest"
created_zip=1
printf 'Packaged %s and %s\n' "$bundle_dest" "$zip_dest"
