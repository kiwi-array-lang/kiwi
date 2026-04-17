#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${KIWI_DEPS_DIR:-}" ]]; then
  if [[ "$KIWI_DEPS_DIR" = /* ]]; then
    DEPS_DIR="$KIWI_DEPS_DIR"
  else
    DEPS_DIR="$ROOT/$KIWI_DEPS_DIR"
  fi
else
  DEPS_DIR="$ROOT/.deps"
fi

DUCKDB_VERSION="${KIWI_DUCKDB_VERSION:-1.5.1}"
DUCKDB_DIR="$DEPS_DIR/duckdb"

detect_asset_name() {
  local requested_platform="${KIWI_DUCKDB_PLATFORM:-}"
  local host_os
  local host_arch
  case "$requested_platform" in
    ""|host)
      host_os="$(uname -s)"
      host_arch="$(uname -m)"
      ;;
    macos|macos-aarch64|macos-universal|darwin|darwin-universal)
      printf 'libduckdb-osx-universal.zip\n'
      return
      ;;
    linux-x86_64|linux-amd64|linux-x64)
      printf 'libduckdb-linux-amd64.zip\n'
      return
      ;;
    linux-aarch64|linux-arm64)
      printf 'libduckdb-linux-arm64.zip\n'
      return
      ;;
    *)
      printf 'unsupported KIWI_DUCKDB_PLATFORM: %s\n' "$requested_platform" >&2
      exit 1
      ;;
  esac

  case "$host_os" in
    Darwin)
      printf 'libduckdb-osx-universal.zip\n'
      ;;
    Linux)
      case "$host_arch" in
        x86_64|amd64)
          printf 'libduckdb-linux-amd64.zip\n'
          ;;
        aarch64|arm64)
          printf 'libduckdb-linux-arm64.zip\n'
          ;;
        *)
          printf 'unsupported Linux arch for DuckDB bootstrap: %s\n' "$host_arch" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      printf 'unsupported host OS for DuckDB bootstrap: %s\n' "$host_os" >&2
      exit 1
      ;;
  esac
}

asset_name="${KIWI_DUCKDB_ASSET_NAME:-$(detect_asset_name)}"
asset_url="${KIWI_DUCKDB_URL:-https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/${asset_name}}"
version_stamp="${DUCKDB_VERSION}:${asset_name}:${asset_url}"
version_file="$DUCKDB_DIR/.version"

if [[ -f "$version_file" ]] && [[ "$(cat "$version_file")" == "$version_stamp" ]] && [[ -f "$DUCKDB_DIR/include/duckdb.h" ]]; then
  if compgen -G "$DUCKDB_DIR/lib/libduckdb.*" >/dev/null; then
    printf 'DuckDB already bootstrapped at %s\n' "$DUCKDB_DIR"
    exit 0
  fi
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

archive_path="$tmpdir/$asset_name"
extract_dir="$tmpdir/extract"

mkdir -p "$extract_dir"
curl -fsSL "$asset_url" -o "$archive_path"
unzip -q "$archive_path" -d "$extract_dir"

lib_path="$(find "$extract_dir" -maxdepth 2 -type f \( -name 'libduckdb.dylib' -o -name 'libduckdb.so' \) | head -n1)"
[[ -n "$lib_path" ]] || { printf 'duckdb bootstrap archive did not contain libduckdb\n' >&2; exit 1; }
[[ -f "$extract_dir/duckdb.h" ]] || { printf 'duckdb bootstrap archive did not contain duckdb.h\n' >&2; exit 1; }

rm -rf "$DUCKDB_DIR"
mkdir -p "$DUCKDB_DIR/include" "$DUCKDB_DIR/lib"

cp "$extract_dir/duckdb.h" "$DUCKDB_DIR/include/duckdb.h"
if [[ -f "$extract_dir/duckdb.hpp" ]]; then
  cp "$extract_dir/duckdb.hpp" "$DUCKDB_DIR/include/duckdb.hpp"
fi
cp "$lib_path" "$DUCKDB_DIR/lib/"
printf '%s\n' "$version_stamp" > "$version_file"

printf 'bootstrapped DuckDB %s at %s\n' "$DUCKDB_VERSION" "$DUCKDB_DIR"
