#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIWI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ -f "$KIWI_ROOT/scripts/kiwi_cuda_defaults.sh" ]]; then
  WORKSPACE_ROOT="$KIWI_ROOT"
else
  WORKSPACE_ROOT="$(cd "$KIWI_ROOT/../.." && pwd)"
fi
CORE_DIR="$KIWI_ROOT/python/runtime"
DEFAULT_JUPYTER_DIR="$WORKSPACE_ROOT/extensions/jupyter-kiwi"
JUPYTER_DIR="${KIWI_ARRAY_WHEEL_JUPYTER_DIR:-$DEFAULT_JUPYTER_DIR}"
HOST_DIR="$KIWI_ROOT/python/host"
CPU_DIR="$KIWI_ROOT/python/cpu"
METAL_DIR="$KIWI_ROOT/python/metal"
CUDA12_DIR="$KIWI_ROOT/python/cuda12"
DIST_DIR="${KIWI_ARRAY_WHEEL_DIST_DIR:-$KIWI_ROOT/out/python-wheels/dist}"
PREFIX_EXPLICIT=0
if [[ -n "${KIWI_ARRAY_WHEEL_PREFIX:-}" ]]; then
  PREFIX_EXPLICIT=1
fi
PREFIX="${KIWI_ARRAY_WHEEL_PREFIX:-$KIWI_ROOT/out/python-wheels/native-prefix}"
OPTIMIZE="${KIWI_ARRAY_WHEEL_OPTIMIZE:-ReleaseFast}"
TARGET="${KIWI_ARRAY_WHEEL_TARGET:-}"
RUNTIME_BACKEND="${KIWI_ARRAY_WHEEL_RUNTIME_BACKEND:-host}"
MLX_BACKEND="${KIWI_ARRAY_WHEEL_MLX_BACKEND:-auto}"
MLXC_MINI_BRIDGE="${KIWI_ARRAY_WHEEL_MLXC_MINI_BRIDGE:-}"
APPLE_SDK="${KIWI_ARRAY_WHEEL_APPLE_SDK:-${SDKROOT:-}}"
UV_BIN="${UV:-uv}"
SKIP_NATIVE_BUILD="${KIWI_ARRAY_WHEEL_SKIP_NATIVE_BUILD:-0}"
ALLOW_MISSING_DUCKDB="${KIWI_ARRAY_ALLOW_MISSING_DUCKDB:-0}"
BUILD_JUPYTER="${KIWI_ARRAY_WHEEL_BUILD_JUPYTER:-1}"
RUNTIME_PACKAGE_TARGET="${KIWI_ARRAY_WHEEL_RUNTIME_PACKAGE:-host}"
BUILD_CORE="${KIWI_ARRAY_WHEEL_BUILD_CORE:-}"
BUILD_HOST="${KIWI_ARRAY_WHEEL_BUILD_HOST:-}"
BUILD_CPU="${KIWI_ARRAY_WHEEL_BUILD_CPU:-}"
BUILD_METAL="${KIWI_ARRAY_WHEEL_BUILD_METAL:-}"
BUILD_CUDA12="${KIWI_ARRAY_WHEEL_BUILD_CUDA12:-${KIWI_ARRAY_WHEEL_BUILD_RUNTIME_MLX_CUDA12:-}}"
UV_PROJECT_ENVIRONMENT="${KIWI_ARRAY_WHEEL_UV_PROJECT_ENVIRONMENT:-${UV_PROJECT_ENVIRONMENT:-$KIWI_ROOT/out/python-wheels/.uv-env-$(uname -s)-$(uname -m)-$RUNTIME_PACKAGE_TARGET}}"
export UV_PROJECT_ENVIRONMENT

if [ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ] && [[ "$TARGET" =~ -macos\.([0-9]+)\.([0-9]+) ]]; then
  export MACOSX_DEPLOYMENT_TARGET="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
fi

cleanup_python_build_artifacts() {
  local paths=(
    "$CORE_DIR/build" \
    "$CORE_DIR/src/kiwi_array.egg-info" \
    "$HOST_DIR/build" \
    "$HOST_DIR/src/kiwi_array_host.egg-info" \
    "$CPU_DIR/build" \
    "$CPU_DIR/src/kiwi_array_cpu.egg-info" \
    "$METAL_DIR/build" \
    "$METAL_DIR/src/kiwi_array_metal.egg-info" \
    "$CUDA12_DIR/build" \
    "$CUDA12_DIR/src/kiwi_array_cuda12.egg-info"
  )
  if [ -n "$JUPYTER_DIR" ]; then
    paths+=(
      "$JUPYTER_DIR/build"
      "$JUPYTER_DIR/src/kiwi_array_jupyter.egg-info"
      "$JUPYTER_DIR/src/kiwi_array_jupyter_kernel.egg-info"
    )
  fi
  rm -rf "${paths[@]}"
}

trap cleanup_python_build_artifacts EXIT

case "$RUNTIME_BACKEND" in
  host|mlx) ;;
  *)
    echo "unsupported KIWI_ARRAY_WHEEL_RUNTIME_BACKEND: $RUNTIME_BACKEND" >&2
    exit 2
    ;;
esac

case "$MLX_BACKEND" in
  auto|cpu|metal|cuda) ;;
  *)
    echo "unsupported KIWI_ARRAY_WHEEL_MLX_BACKEND: $MLX_BACKEND" >&2
    exit 2
    ;;
esac

case "$RUNTIME_PACKAGE_TARGET" in
  core)
    STAGE_RUNTIME_PACKAGE=""
    BUILD_CORE="${BUILD_CORE:-1}"
    BUILD_HOST="${BUILD_HOST:-0}"
    BUILD_CPU="${BUILD_CPU:-0}"
    BUILD_METAL="${BUILD_METAL:-0}"
    BUILD_CUDA12="${BUILD_CUDA12:-0}"
    ;;
  host)
    STAGE_RUNTIME_PACKAGE="$HOST_DIR/src/kiwi_array_host"
    BUILD_CORE="${BUILD_CORE:-1}"
    BUILD_HOST="${BUILD_HOST:-1}"
    BUILD_CPU="${BUILD_CPU:-0}"
    BUILD_METAL="${BUILD_METAL:-0}"
    BUILD_CUDA12="${BUILD_CUDA12:-0}"
    ;;
  cpu)
    STAGE_RUNTIME_PACKAGE="$CPU_DIR/src/kiwi_array_cpu"
    BUILD_CORE="${BUILD_CORE:-0}"
    BUILD_HOST="${BUILD_HOST:-0}"
    BUILD_CPU="${BUILD_CPU:-1}"
    BUILD_METAL="${BUILD_METAL:-0}"
    BUILD_CUDA12="${BUILD_CUDA12:-0}"
    ;;
  metal)
    STAGE_RUNTIME_PACKAGE="$METAL_DIR/src/kiwi_array_metal"
    BUILD_CORE="${BUILD_CORE:-0}"
    BUILD_HOST="${BUILD_HOST:-0}"
    BUILD_CPU="${BUILD_CPU:-0}"
    BUILD_METAL="${BUILD_METAL:-1}"
    BUILD_CUDA12="${BUILD_CUDA12:-0}"
    ;;
  cuda12|mlx-cuda12)
    STAGE_RUNTIME_PACKAGE="$CUDA12_DIR/src/kiwi_array_cuda12"
    BUILD_CORE="${BUILD_CORE:-0}"
    BUILD_HOST="${BUILD_HOST:-0}"
    BUILD_CPU="${BUILD_CPU:-0}"
    BUILD_METAL="${BUILD_METAL:-0}"
    BUILD_CUDA12="${BUILD_CUDA12:-1}"
    ;;
  *)
    echo "unsupported KIWI_ARRAY_WHEEL_RUNTIME_PACKAGE: $RUNTIME_PACKAGE_TARGET" >&2
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
  "-Dcli-name=kiwi"
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

if [ -n "$TARGET" ]; then
  BUILD_ARGS+=("-Dtarget=$TARGET")
fi

if [ -n "$MLXC_MINI_BRIDGE" ]; then
  BUILD_ARGS+=("-Dmlxc-mini-bridge=$MLXC_MINI_BRIDGE")
fi

if [ -n "$APPLE_SDK" ]; then
  BUILD_ARGS+=("-Dapple-sdk=$APPLE_SDK")
fi

if [ -n "$DUCKDB_PREFIX" ]; then
  BUILD_ARGS+=("-Dduckdb-prefix=$DUCKDB_PREFIX")
elif [ -d "$KIWI_ROOT/.deps/duckdb" ]; then
  BUILD_ARGS+=("-Dduckdb-prefix=$KIWI_ROOT/.deps/duckdb")
fi

mkdir -p "$DIST_DIR"
rm -f \
  "$DIST_DIR"/kiwi_array-*.whl \
  "$DIST_DIR"/kiwi_array_jupyter-*.whl \
  "$DIST_DIR"/kiwi_array_host-*.whl \
  "$DIST_DIR"/kiwi_array_cpu-*.whl \
  "$DIST_DIR"/kiwi_array_metal-*.whl \
  "$DIST_DIR"/kiwi_array_cuda12-*.whl
cleanup_python_build_artifacts

if [ -n "$STAGE_RUNTIME_PACKAGE" ] && [ "$SKIP_NATIVE_BUILD" != "1" ]; then
  rm -rf "$PREFIX"
  (cd "$KIWI_ROOT" && "$ZIG_BIN" "${BUILD_ARGS[@]}")
elif [ -n "$STAGE_RUNTIME_PACKAGE" ] && [ "$PREFIX_EXPLICIT" != "1" ]; then
  PREFIX="$KIWI_ROOT/zig-out"
fi

if [ -n "$STAGE_RUNTIME_PACKAGE" ]; then
  STAGE_ARGS=(
    "$SCRIPT_DIR/stage_runtime_payload.py"
    "--prefix"
    "$PREFIX"
    "--runtime-backend"
    "$RUNTIME_BACKEND"
    "--runtime-package"
    "$STAGE_RUNTIME_PACKAGE"
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
fi

if [ "$BUILD_CORE" != "0" ]; then
  "$UV_BIN" build --wheel --out-dir "$DIST_DIR" "$CORE_DIR"
fi
if [ "$BUILD_HOST" != "0" ]; then
  "$UV_BIN" build --wheel --out-dir "$DIST_DIR" "$HOST_DIR"
fi
if [ "$BUILD_CPU" != "0" ]; then
  "$UV_BIN" build --wheel --out-dir "$DIST_DIR" "$CPU_DIR"
fi
if [ "$BUILD_METAL" != "0" ]; then
  "$UV_BIN" build --wheel --out-dir "$DIST_DIR" "$METAL_DIR"
fi
if [ "$BUILD_CUDA12" != "0" ]; then
  "$UV_BIN" build --wheel --out-dir "$DIST_DIR" "$CUDA12_DIR"
fi
if [ "$BUILD_JUPYTER" != "0" ] && [ "$BUILD_CORE" != "0" ]; then
  if [ ! -f "$JUPYTER_DIR/pyproject.toml" ]; then
    echo "kiwi-array-jupyter source not found: $JUPYTER_DIR" >&2
    echo "set KIWI_ARRAY_WHEEL_JUPYTER_DIR or KIWI_ARRAY_WHEEL_BUILD_JUPYTER=0" >&2
    exit 1
  fi
  "$UV_BIN" build --wheel --out-dir "$DIST_DIR" "$JUPYTER_DIR"
fi

find "$DIST_DIR" -maxdepth 1 -type f -name '*.whl' -print | sort
