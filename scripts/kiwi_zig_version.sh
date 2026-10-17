#!/usr/bin/env bash

# Shared reader for the repository's authoritative Zig snapshot pin.

KIWI_ZIG_VERSION_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIWI_ZIG_VERSION_FILE="${KIWI_ZIG_VERSION_FILE:-$KIWI_ZIG_VERSION_HELPER_DIR/../tools/zig-version}"

if [[ ! -r "$KIWI_ZIG_VERSION_FILE" ]]; then
  printf 'missing Kiwi Zig version file: %s\n' "$KIWI_ZIG_VERSION_FILE" >&2
  return 1
fi

IFS= read -r KIWI_ZIG_VERSION <"$KIWI_ZIG_VERSION_FILE"
case "$KIWI_ZIG_VERSION" in
  ""|*[!0-9A-Za-z.+-]*)
    printf 'invalid Kiwi Zig version in %s: %s\n' "$KIWI_ZIG_VERSION_FILE" "$KIWI_ZIG_VERSION" >&2
    return 1
    ;;
esac

KIWI_ZIG_DOCKER_TAG_VERSION="${KIWI_ZIG_VERSION//+/-}"
unset KIWI_ZIG_VERSION_HELPER_DIR
