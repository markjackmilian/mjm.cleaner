#!/usr/bin/env bash

normalize_version() {
    local version="${1#v}"

    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Versione non valida: '$1' (formato atteso: v1.2.3 o 1.2.3)" >&2
        return 1
    fi

    printf '%s\n' "$version"
}

artifact_basename() {
    local rid="$1"
    local version="$2"
    local architecture

    case "$rid" in
        osx-arm64) architecture="arm64" ;;
        osx-x64) architecture="x64" ;;
        *)
            echo "Runtime non supportato: '$rid'" >&2
            return 1
            ;;
    esac

    printf 'mjm.cleaner-%s-macos-%s\n' "$version" "$architecture"
}
