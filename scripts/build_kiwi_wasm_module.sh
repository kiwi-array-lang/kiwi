#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <input.wasm> <output.js>" >&2
  exit 1
fi

INPUT_WASM="$1"
OUT_JS="$2"

mkdir -p "$(dirname "$OUT_JS")"

BASE64="$(base64 < "$INPUT_WASM" | tr -d '\n')"

cat > "$OUT_JS" <<EOF
(function (root) {
  "use strict";
  const base64 = "$BASE64";
  if (typeof module !== "undefined" && module.exports) {
    module.exports = base64;
  }
  root.KiwiWasmModuleBase64 = base64;
})(typeof globalThis !== "undefined" ? globalThis : this);
EOF
