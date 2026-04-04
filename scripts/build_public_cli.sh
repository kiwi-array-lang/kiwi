#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BACKEND="cpu"
LINKAGE="static"
OPTIMIZE="ReleaseFast"
PREFIX="${KIWI_PUBLIC_PREFIX:-$ROOT/out/public-cli/kiwi-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)}"
DEPS_DIR="${KIWI_PUBLIC_DEPS_DIR:-}"
LOCK_FILE="${KIWI_PUBLIC_LOCK_FILE:-}"

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

  printf 'unable to locate zig; set ZIG_BIN or install zig on PATH\n' >&2
  exit 1
}

usage() {
  cat >&2 <<EOF
usage: ${BASH_SOURCE[0]} [--backend cpu|metal] [--linkage static|dynamic] [--optimize ReleaseFast|ReleaseSmall|ReleaseSafe|Debug] [--prefix <path>] [--deps-dir <path>]

default behavior:
  - bootstraps pinned MLX deps for kiwi-zig-main
  - builds the standalone CLI bundle as bin/kiwi
  - defaults to a static CPU package for easy redistribution
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)
      [[ $# -ge 2 ]] || usage
      BACKEND="$2"
      shift 2
      ;;
    --linkage)
      [[ $# -ge 2 ]] || usage
      LINKAGE="$2"
      shift 2
      ;;
    --optimize)
      [[ $# -ge 2 ]] || usage
      OPTIMIZE="$2"
      shift 2
      ;;
    --prefix)
      [[ $# -ge 2 ]] || usage
      PREFIX="$2"
      shift 2
      ;;
    --deps-dir)
      [[ $# -ge 2 ]] || usage
      DEPS_DIR="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

case "$BACKEND" in
  cpu|metal)
    ;;
  *)
    printf 'unsupported backend: %s\n' "$BACKEND" >&2
    exit 1
    ;;
esac

case "$LINKAGE" in
  static|dynamic)
    ;;
  *)
    printf 'unsupported linkage: %s\n' "$LINKAGE" >&2
    exit 1
    ;;
esac

if [[ -z "$DEPS_DIR" ]]; then
  DEPS_DIR="$ROOT/.deps-public/${BACKEND}-${LINKAGE}"
fi
if [[ -z "$LOCK_FILE" && -f "$ROOT/deps.public.lock.toml" ]]; then
  LOCK_FILE="$ROOT/deps.public.lock.toml"
fi

ZIG_BIN="$(choose_zig_bin)"

export KIWI_MLX_BACKEND="$BACKEND"
export KIWI_MLX_LINKAGE="$([[ "$LINKAGE" = dynamic ]] && printf 'shared' || printf 'static')"
export KIWI_DEPS_DIR="$DEPS_DIR"

rm -rf "$PREFIX"

if [[ -n "$LOCK_FILE" ]]; then
  bash "$ROOT/scripts/bootstrap_deps.sh" --lock-file "$LOCK_FILE"
else
  bash "$ROOT/scripts/bootstrap_deps.sh"
fi

cd "$ROOT"
"$ZIG_BIN" build \
  -Dpublic-cli=true \
  -Dstrip-instrumentation=true \
  "-Dmlx-prefix=$DEPS_DIR/mlx" \
  "-Dmlx-c-include=$DEPS_DIR/mlx-c" \
  "-Dmlx-backend=$BACKEND" \
  "-Dmlx-linkage=$LINKAGE" \
  "-Doptimize=$OPTIMIZE" \
  --prefix "$PREFIX"

mkdir -p "$PREFIX/lib"
if [[ "$LINKAGE" = dynamic ]]; then
  cp "$DEPS_DIR/mlx/lib/libmlx.dylib" "$PREFIX/lib/libmlx.dylib"
fi
if [[ "$BACKEND" = metal ]]; then
  cp "$DEPS_DIR/mlx/lib/mlx.metallib" "$PREFIX/lib/mlx.metallib"
fi
if [[ -z "$(find "$PREFIX/lib" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  rmdir "$PREFIX/lib"
fi

printf 'built public CLI at %s\n' "$PREFIX"
