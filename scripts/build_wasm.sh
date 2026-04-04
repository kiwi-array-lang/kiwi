#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

choose_zig_bin() {
  if [[ -n "${ZIG_BIN:-}" ]]; then
    printf '%s\n' "$ZIG_BIN"
    return
  fi

  if [[ -x "$ROOT/tools/zig" ]]; then
    printf '%s\n' "$ROOT/tools/zig"
    return
  fi

  if command -v zig >/dev/null 2>&1; then
    command -v zig
    return
  fi

  echo "unable to locate zig; set ZIG_BIN or install zig on PATH" >&2
  exit 1
}

ZIG_BIN="$(choose_zig_bin)"

cd "$ROOT"
"$ZIG_BIN" build wasm "$@"
