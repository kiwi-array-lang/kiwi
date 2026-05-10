#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIWI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ -f "$KIWI_ROOT/scripts/kiwi_cuda_defaults.sh" ]]; then
  WORKSPACE_ROOT="$KIWI_ROOT"
else
  WORKSPACE_ROOT="$(cd "$KIWI_ROOT/../.." && pwd)"
fi
RUNTIME_DIR="$KIWI_ROOT/python/runtime"
JUPYTER_DIR="$KIWI_ROOT/python/jupyter"
DIST_DIR="${KIWILANG_WHEEL_DIST_DIR:-$KIWI_ROOT/out/python-wheels/dist}"
PREFIX="${KIWILANG_WHEEL_PREFIX:-$KIWI_ROOT/out/python-wheels/native-prefix}"
OPTIMIZE="${KIWILANG_WHEEL_OPTIMIZE:-ReleaseFast}"
RUNTIME_BACKEND="${KIWILANG_WHEEL_RUNTIME_BACKEND:-mlx}"
MLX_BACKEND="${KIWILANG_WHEEL_MLX_BACKEND:-auto}"
MLXC_MINI_BRIDGE="${KIWILANG_WHEEL_MLXC_MINI_BRIDGE:-}"
UV_BIN="${UV:-uv}"
SKIP_NATIVE_BUILD="${KIWILANG_WHEEL_SKIP_NATIVE_BUILD:-0}"
ALLOW_MISSING_DUCKDB="${KIWILANG_ALLOW_MISSING_DUCKDB:-0}"
BUILD_JUPYTER="${KIWILANG_WHEEL_BUILD_JUPYTER:-1}"

cleanup_python_build_artifacts() {
  rm -rf \
    "$RUNTIME_DIR/build" \
    "$RUNTIME_DIR/src/kiwilang.egg-info" \
    "$JUPYTER_DIR/build" \
    "$JUPYTER_DIR/src/kiwilang_jupyter_kernel.egg-info"
}

trap cleanup_python_build_artifacts EXIT

case "$RUNTIME_BACKEND" in
  host|mlx) ;;
  *)
    echo "unsupported KIWILANG_WHEEL_RUNTIME_BACKEND: $RUNTIME_BACKEND" >&2
    exit 2
    ;;
esac

case "$MLX_BACKEND" in
  auto|cpu|metal|cuda) ;;
  *)
    echo "unsupported KIWILANG_WHEEL_MLX_BACKEND: $MLX_BACKEND" >&2
    exit 2
    ;;
esac

for arg in "$@"; do
  case "$arg" in
    --skip-native-build)
      SKIP_NATIVE_BUILD=1
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if [ -z "${KIWI_ZIG:-}" ]; then
  if [ -x "$WORKSPACE_ROOT/tools/zig" ]; then
    ZIG_BIN="$WORKSPACE_ROOT/tools/zig"
  elif command -v zig >/dev/null 2>&1; then
    ZIG_BIN="$(command -v zig)"
  else
    ZIG_BIN="zig"
  fi
else
  ZIG_BIN="$KIWI_ZIG"
fi

MLX_PREFIX="${KIWI_MLX_PREFIX:-}"
if [ -z "$MLX_PREFIX" ]; then
  case "$(uname -s)" in
    Linux)
      case "$(uname -m)" in
        aarch64|arm64) MLX_ARCH="aarch64" ;;
        *) MLX_ARCH="x86_64" ;;
      esac
      MLX_ARTIFACT_SUFFIX=""
      if [ "$MLX_BACKEND" = "cuda" ]; then
        MLX_ARTIFACT_SUFFIX="-cuda"
      fi
      DEFAULT_MLX_PREFIX="$WORKSPACE_ROOT/.artifacts/mlx/linux-$MLX_ARCH$MLX_ARTIFACT_SUFFIX-install"
      ;;
    *)
      DEFAULT_MLX_PREFIX="$WORKSPACE_ROOT/.artifacts/mlx/macos-default-install"
      ;;
  esac
  if [ ! -d "$DEFAULT_MLX_PREFIX" ]; then
    DEFAULT_MLX_PREFIX="$KIWI_ROOT/.deps/mlx"
  fi
  MLX_PREFIX="$DEFAULT_MLX_PREFIX"
fi

MLX_C_INCLUDE="${KIWI_MLX_C_INCLUDE:-}"
if [ -z "$MLX_C_INCLUDE" ]; then
  if [ -d "$WORKSPACE_ROOT/vendor/mlx-c" ]; then
    MLX_C_INCLUDE="$WORKSPACE_ROOT/vendor/mlx-c"
  else
    MLX_C_INCLUDE="$KIWI_ROOT/.deps/mlx-c"
  fi
fi
DUCKDB_PREFIX="${KIWI_DUCKDB_PREFIX:-}"

BUILD_ARGS=(
  build
  "--seed"
  "0"
  "-Doptimize=$OPTIMIZE"
  "-Dpublic-cli=true"
  "-Dinstall-sdk=true"
  "-Druntime-backend=$RUNTIME_BACKEND"
  "-Dmlx-backend=$MLX_BACKEND"
  "-Dstrip=true"
  "-Dstrip-instrumentation=true"
  "-Dmlx-prefix=$MLX_PREFIX"
  "-Dmlx-c-include=$MLX_C_INCLUDE"
  "--prefix"
  "$PREFIX"
)

if [ -n "$MLXC_MINI_BRIDGE" ]; then
  BUILD_ARGS+=("-Dmlxc-mini-bridge=$MLXC_MINI_BRIDGE")
fi

if [ -n "$DUCKDB_PREFIX" ]; then
  BUILD_ARGS+=("-Dduckdb-prefix=$DUCKDB_PREFIX")
elif [ -d "$KIWI_ROOT/.deps/duckdb" ]; then
  BUILD_ARGS+=("-Dduckdb-prefix=$KIWI_ROOT/.deps/duckdb")
fi

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/kiwilang-*.whl "$DIST_DIR"/kiwilang_jupyter_kernel-*.whl
cleanup_python_build_artifacts

if [ "$SKIP_NATIVE_BUILD" != "1" ]; then
  rm -rf "$PREFIX"
  (cd "$KIWI_ROOT" && "$ZIG_BIN" "${BUILD_ARGS[@]}")
else
  PREFIX="$KIWI_ROOT/zig-out"
fi

STAGE_ARGS=(
  "$SCRIPT_DIR/stage_runtime_payload.py"
  "--prefix"
  "$PREFIX"
  "--runtime-backend"
  "$RUNTIME_BACKEND"
  "--mlx-prefix"
  "$MLX_PREFIX"
)

if [ -n "$DUCKDB_PREFIX" ]; then
  STAGE_ARGS+=("--duckdb-prefix" "$DUCKDB_PREFIX")
fi
if [ "$ALLOW_MISSING_DUCKDB" = "1" ]; then
  STAGE_ARGS+=("--allow-missing-duckdb")
fi

"$UV_BIN" run --python 3.11 python "${STAGE_ARGS[@]}"
"$UV_BIN" build --wheel --out-dir "$DIST_DIR" "$RUNTIME_DIR"
if [ "$BUILD_JUPYTER" != "0" ]; then
  "$UV_BIN" build --wheel --out-dir "$DIST_DIR" "$JUPYTER_DIR"
fi

find "$DIST_DIR" -maxdepth 1 -type f -name '*.whl' -print | sort
