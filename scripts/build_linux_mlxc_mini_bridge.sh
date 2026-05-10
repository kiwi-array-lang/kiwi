#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
MLX_PREFIX="${1:-${MLX_INSTALL_PREFIX:-}}"
BRIDGE_LIB_NAME="${2:-${MLXC_MINI_BRIDGE_LIB:-kiwi_mlx_bridge}}"

if [[ "$(uname -s)" != "Linux" ]]; then
  printf 'scripts/build_linux_mlxc_mini_bridge.sh must run on Linux\n' >&2
  exit 1
fi

if [[ -z "$MLX_PREFIX" ]]; then
  printf 'usage: %s <mlx-prefix> [bridge-lib-name]\n' "${BASH_SOURCE[0]}" >&2
  exit 1
fi

if [[ ! -d "$MLX_PREFIX/include" || ! -d "$MLX_PREFIX/lib" ]]; then
  printf 'invalid MLX prefix: %s\n' "$MLX_PREFIX" >&2
  exit 1
fi

CXX_BIN="${CXX_BIN:-$(command -v clang++ || true)}"
if [[ -z "$CXX_BIN" ]]; then
  printf 'unable to locate clang++; install it or set CXX_BIN\n' >&2
  exit 1
fi

SOURCE_ROOT="${KIWI_SOURCE_ROOT:-$ROOT}"
OUTPUT_LIB="$MLX_PREFIX/lib/lib${BRIDGE_LIB_NAME}.so"
if [[ -f "$SOURCE_ROOT/csrc/mlxc_mini.cpp" ]]; then
  BRIDGE_SOURCE="$SOURCE_ROOT/csrc/mlxc_mini.cpp"
else
  printf 'missing Kiwi MLX C bridge source under %s; set KIWI_SOURCE_ROOT if needed\n' "$SOURCE_ROOT" >&2
  exit 1
fi
if [[ -n "${MLX_C_INCLUDE_ROOT:-}" && -d "$MLX_C_INCLUDE_ROOT/mlx" ]]; then
  MLX_C_INCLUDE_ROOT="$(cd "$MLX_C_INCLUDE_ROOT" && pwd)"
elif [[ -d "$ROOT/vendor/mlx-c/mlx" ]]; then
  MLX_C_INCLUDE_ROOT="$ROOT/vendor/mlx-c"
elif [[ -d "$ROOT/.deps/mlx-c/mlx" ]]; then
  MLX_C_INCLUDE_ROOT="$ROOT/.deps/mlx-c"
elif [[ -d "$ROOT/.deps/src/mlx-c/mlx" ]]; then
  MLX_C_INCLUDE_ROOT="$ROOT/.deps/src/mlx-c"
else
  printf 'missing mlx-c headers; run scripts/bootstrap_deps.sh --fetch-only first or set MLX_C_INCLUDE_ROOT\n' >&2
  exit 1
fi
MLX_C_HEADERS_DIR="$MLX_C_INCLUDE_ROOT/mlx"
MLX_CPP_HEADERS_DIR="$MLX_PREFIX/include/mlx"
CXXFLAGS=(
  -std=c++20
  -O3
  -fPIC
  -shared
  -Wl,-soname,"lib${BRIDGE_LIB_NAME}.so"
  -Wl,-rpath,'$ORIGIN'
)

case "$(basename "$CXX_BIN")" in
  clang++|clang++-*)
    CXXFLAGS+=(-stdlib=libstdc++)
    ;;
esac

bridge_needs_rebuild() {
  [[ ! -f "$OUTPUT_LIB" ]] && return 0
  [[ "$BRIDGE_SOURCE" -nt "$OUTPUT_LIB" ]] && return 0
  [[ "$MLX_PREFIX/lib/libmlx.so" -nt "$OUTPUT_LIB" ]] && return 0
  [[ "${BASH_SOURCE[0]}" -nt "$OUTPUT_LIB" ]] && return 0
  if find "$MLX_C_HEADERS_DIR" "$MLX_CPP_HEADERS_DIR" -type f -newer "$OUTPUT_LIB" -print -quit | grep -q .; then
    return 0
  fi
  return 1
}

if ! bridge_needs_rebuild; then
  printf 'Reusing Linux MLX bridge library at %s\n' "$OUTPUT_LIB"
  exit 0
fi

"$CXX_BIN" \
  "${CXXFLAGS[@]}" \
  -I "$MLX_C_INCLUDE_ROOT" \
  -I "$MLX_PREFIX/include" \
  "$BRIDGE_SOURCE" \
  -L "$MLX_PREFIX/lib" \
  -lmlx \
  -o "$OUTPUT_LIB"

printf 'Built Linux MLX bridge library at %s\n' "$OUTPUT_LIB"
