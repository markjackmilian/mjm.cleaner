#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=../../build/bundle-config.sh
source "$ROOT/build/bundle-config.sh"

assert_eq() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $message: expected '$expected', got '$actual'" >&2
        exit 1
    fi
}

assert_fails() {
    local message="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        echo "FAIL: $message: command unexpectedly succeeded" >&2
        exit 1
    fi
}

assert_eq "1.2.3" "$(normalize_version v1.2.3)" "strip the release tag prefix"
assert_eq "1.2.3" "$(normalize_version 1.2.3)" "accept an unprefixed version"
assert_fails "reject a malformed version" normalize_version release-1.2.3
assert_fails "reject a prerelease version unsupported by Info.plist" normalize_version 1.2.3-beta.1

assert_eq \
    "mjm.cleaner-1.2.3-macos-arm64" \
    "$(artifact_basename osx-arm64 1.2.3)" \
    "name the Apple Silicon artifact"
assert_eq \
    "mjm.cleaner-1.2.3-macos-x64" \
    "$(artifact_basename osx-x64 1.2.3)" \
    "name the Intel artifact"
assert_fails "reject an unsupported RID" artifact_basename linux-x64 1.2.3

echo "bundle-config tests: PASS"
