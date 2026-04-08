#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <input.wasm> <output.wasm>" >&2
  exit 1
fi

INPUT_WASM="$1"
OUT_WASM="$2"
LEGACY_OUT_JS="${OUT_WASM%.wasm}.js"

mkdir -p "$(dirname "$OUT_WASM")"

cp "$INPUT_WASM" "$OUT_WASM"
rm -f "$LEGACY_OUT_JS"
