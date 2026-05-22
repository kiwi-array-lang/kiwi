#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
source "$ROOT/scripts/kiwi_cuda_defaults.sh"

if [[ -d "${MLX_SRC_DIR:-}" ]]; then
  MLX_SRC_DIR="$(cd "$MLX_SRC_DIR" && pwd)"
elif [[ -d "$ROOT/vendor/mlx" ]]; then
  MLX_SRC_DIR="$ROOT/vendor/mlx"
elif [[ -d "$ROOT/.deps/src/mlx" ]]; then
  MLX_SRC_DIR="$ROOT/.deps/src/mlx"
else
  printf 'missing MLX source; run scripts/bootstrap_deps.sh --fetch-only first or set MLX_SRC_DIR\n' >&2
  exit 1
fi
MLX_BACKEND="${MLX_BACKEND:-cpu}"
CUDA_ARCHITECTURES_DEFAULT="$KIWI_HOSTED_NOTEBOOK_CUDA_ARCHITECTURES"

if [[ "$(uname -s)" != "Linux" ]]; then
  printf 'scripts/build_linux_mlx.sh must run on Linux\n' >&2
  exit 1
fi

case "$(uname -m)" in
  aarch64|arm64) MLX_ARCH="aarch64" ;;
  x86_64|amd64) MLX_ARCH="x86_64" ;;
  *)
    printf 'unsupported Linux architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

find_cmake() {
  if [[ -n "${CMAKE_BIN:-}" ]]; then
    printf '%s\n' "$CMAKE_BIN"
    return
  fi

  if command -v cmake >/dev/null 2>&1; then
    command -v cmake
    return
  fi

  printf 'unable to locate cmake; install it or set CMAKE_BIN\n' >&2
  exit 1
}

CMAKE_BIN="$(find_cmake)"
EXTRA_CMAKE_ARGS=()
TOOLCHAIN_CMAKE_ARGS=()
EXPECTED_C_COMPILER=""
EXPECTED_CXX_COMPILER=""
EXPECTED_CUDA_COMPILER=""
EXPECTED_CUDA_HOST_COMPILER=""
EXPECTED_CUDA_ARCHITECTURES=""
EXPECTED_CUDA_KERNEL_PROFILE=""
EXPECTED_SOURCE_DIR="$MLX_SRC_DIR"

configure_clang_toolchain() {
  local clang_bin="${CC:-$(command -v clang || true)}"
  local clangxx_bin="${CXX:-$(command -v clang++ || true)}"

  if [[ -z "$clang_bin" || -z "$clangxx_bin" ]]; then
    printf 'clang/clang++ are required for Linux MLX builds; install them or set CC/CXX\n' >&2
    exit 1
  fi
  TOOLCHAIN_CMAKE_ARGS=(
    -DCMAKE_C_COMPILER="$clang_bin"
    -DCMAKE_CXX_COMPILER="$clangxx_bin"
  )
  EXPECTED_C_COMPILER="$clang_bin"
  EXPECTED_CXX_COMPILER="$clangxx_bin"
}

case "$MLX_BACKEND" in
  cpu)
    MLX_ARTIFACT_SUFFIX=""
    MLX_BUILD_CPU=ON
    MLX_BUILD_CUDA=OFF
    configure_clang_toolchain
    ;;
  cuda)
    MLX_ARTIFACT_SUFFIX="-cuda"
    MLX_BUILD_CPU=ON
    MLX_BUILD_CUDA=ON
    if ! command -v nvcc >/dev/null 2>&1; then
      printf 'CUDA backend requested but nvcc is unavailable\n' >&2
      exit 1
    fi
    CLANG_BIN="${CUDA_HOST_CC:-$(command -v clang || true)}"
    CLANGXX_BIN="${CUDA_HOST_CXX:-$(command -v clang++ || true)}"
    if [[ -z "$CLANG_BIN" || -z "$CLANGXX_BIN" ]]; then
      printf 'CUDA backend requested but clang/clang++ host compilers are unavailable\n' >&2
      exit 1
    fi
    CUDA_ARCHITECTURES="${MLX_CUDA_ARCHITECTURES:-$CUDA_ARCHITECTURES_DEFAULT}"
    CUDA_KERNEL_PROFILE="${KIWI_MLX_CUDA_KERNEL_PROFILE:-${MLX_CUDA_KERNEL_PROFILE:-$KIWI_HOSTED_NOTEBOOK_CUDA_KERNEL_PROFILE}}"
    TOOLCHAIN_CMAKE_ARGS=(
      -DCMAKE_C_COMPILER="$CLANG_BIN"
      -DCMAKE_CXX_COMPILER="$CLANGXX_BIN"
      -DCMAKE_CUDA_COMPILER="$(command -v nvcc)"
      -DCMAKE_CUDA_HOST_COMPILER="$CLANGXX_BIN"
      -DMLX_CUDA_ARCHITECTURES="$CUDA_ARCHITECTURES"
      -DMLX_CUDA_KERNEL_PROFILE="$CUDA_KERNEL_PROFILE"
    )
    case "$KIWI_CUDA_DISABLE_SM80_QMM" in
      1|true|TRUE|yes|YES|on|ON)
        EXTRA_CMAKE_ARGS+=(-DMLX_KIWI_DISABLE_CUDA_SM80_QMM=ON)
        ;;
      0|false|FALSE|no|NO|off|OFF)
        EXTRA_CMAKE_ARGS+=(-DMLX_KIWI_DISABLE_CUDA_SM80_QMM=OFF)
        ;;
      *)
        printf 'unsupported KIWI_CUDA_DISABLE_SM80_QMM: %s\n' "$KIWI_CUDA_DISABLE_SM80_QMM" >&2
        exit 1
        ;;
    esac
    EXPECTED_C_COMPILER="$CLANG_BIN"
    EXPECTED_CXX_COMPILER="$CLANGXX_BIN"
    EXPECTED_CUDA_COMPILER="$(command -v nvcc)"
    EXPECTED_CUDA_HOST_COMPILER="$CLANGXX_BIN"
    EXPECTED_CUDA_ARCHITECTURES="$CUDA_ARCHITECTURES"
    EXPECTED_CUDA_KERNEL_PROFILE="$CUDA_KERNEL_PROFILE"
    ;;
  *)
    printf 'unsupported MLX_BACKEND: %s\nexpected cpu or cuda\n' "$MLX_BACKEND" >&2
    exit 1
    ;;
esac

if [[ -z "${BUILD_PARALLEL:-}" ]]; then
  case "$MLX_BACKEND" in
    cuda) BUILD_PARALLEL="$KIWI_HOSTED_NOTEBOOK_CUDA_BUILD_PARALLEL" ;;
    *) BUILD_PARALLEL="$(nproc)" ;;
  esac
fi

BUILD_DIR="${MLX_BUILD_DIR:-$ROOT/.artifacts/mlx/linux-${MLX_ARCH}${MLX_ARTIFACT_SUFFIX}-build}"
INSTALL_DIR="${MLX_INSTALL_PREFIX:-$ROOT/.artifacts/mlx/linux-${MLX_ARCH}${MLX_ARTIFACT_SUFFIX}-install}"

cache_var_value() {
  local cache_file="$1"
  local key="$2"
  sed -n "s/^${key}:[^=]*=//p" "$cache_file" | head -n1
}

if [[ -f "$BUILD_DIR/CMakeCache.txt" ]]; then
  CACHE_FILE="$BUILD_DIR/CMakeCache.txt"
  CACHE_C_COMPILER="$(cache_var_value "$CACHE_FILE" CMAKE_C_COMPILER)"
  CACHE_CXX_COMPILER="$(cache_var_value "$CACHE_FILE" CMAKE_CXX_COMPILER)"
  CACHE_CUDA_COMPILER="$(cache_var_value "$CACHE_FILE" CMAKE_CUDA_COMPILER)"
  CACHE_CUDA_HOST_COMPILER="$(cache_var_value "$CACHE_FILE" CMAKE_CUDA_HOST_COMPILER)"
  CACHE_CUDA_ARCHITECTURES="$(cache_var_value "$CACHE_FILE" MLX_CUDA_ARCHITECTURES)"
  CACHE_CUDA_KERNEL_PROFILE="$(cache_var_value "$CACHE_FILE" MLX_CUDA_KERNEL_PROFILE)"
  CACHE_INSTALL_PREFIX="$(cache_var_value "$CACHE_FILE" CMAKE_INSTALL_PREFIX)"
  CACHE_SOURCE_DIR="$(cache_var_value "$CACHE_FILE" CMAKE_HOME_DIRECTORY)"

  if [[ "$CACHE_C_COMPILER" != "$EXPECTED_C_COMPILER" ]] \
    || [[ "$CACHE_CXX_COMPILER" != "$EXPECTED_CXX_COMPILER" ]] \
    || [[ -n "$EXPECTED_CUDA_COMPILER" && "$CACHE_CUDA_COMPILER" != "$EXPECTED_CUDA_COMPILER" ]] \
    || [[ -n "$EXPECTED_CUDA_HOST_COMPILER" && "$CACHE_CUDA_HOST_COMPILER" != "$EXPECTED_CUDA_HOST_COMPILER" ]] \
    || [[ -n "$EXPECTED_CUDA_ARCHITECTURES" && "$CACHE_CUDA_ARCHITECTURES" != "$EXPECTED_CUDA_ARCHITECTURES" ]] \
    || [[ -n "$EXPECTED_CUDA_KERNEL_PROFILE" && "$CACHE_CUDA_KERNEL_PROFILE" != "$EXPECTED_CUDA_KERNEL_PROFILE" ]] \
    || [[ "$CACHE_INSTALL_PREFIX" != "$INSTALL_DIR" ]] \
    || [[ "$CACHE_SOURCE_DIR" != "$EXPECTED_SOURCE_DIR" ]]; then
    rm -rf "$BUILD_DIR"
  fi
fi

maybe_add_fetch_source() {
  local arg_name="$1"
  local env_name="$2"
  shift 2

  local source_dir="${!env_name:-}"
  if [[ -n "$source_dir" && -d "$source_dir" ]]; then
    EXTRA_CMAKE_ARGS+=("-D${arg_name}=$source_dir")
    return
  fi

  local candidate
  for candidate in "$@"; do
    if [[ -d "$candidate" ]]; then
      EXTRA_CMAKE_ARGS+=("-D${arg_name}=$candidate")
      return
    fi
  done
}

maybe_add_fetch_source FETCHCONTENT_SOURCE_DIR_FMT FMT_SOURCE_DIR \
  "$ROOT/.deps/build/mlx/_deps/fmt-src" \
  "$ROOT/.artifacts/mlx/_deps/fmt-src" \
  "$ROOT/.artifacts/mlx/macos-default-build/_deps/fmt-src"
maybe_add_fetch_source FETCHCONTENT_SOURCE_DIR_JSON JSON_SOURCE_DIR \
  "$ROOT/.deps/build/mlx/_deps/json-src" \
  "$ROOT/.artifacts/mlx/_deps/json-src" \
  "$ROOT/.artifacts/mlx/macos-default-build/_deps/json-src"

if [[ -n "${MLX_EXTRA_CMAKE_ARGS:-}" ]]; then
  # Intentional shell splitting: callers pass simple -Dkey=value tokens.
  EXTRA_CMAKE_ARGS+=(${MLX_EXTRA_CMAKE_ARGS})
fi

"$CMAKE_BIN" \
  -S "$MLX_SRC_DIR" \
  -B "$BUILD_DIR" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DBUILD_SHARED_LIBS=ON \
  -DMLX_BUILD_TESTS=OFF \
  -DMLX_BUILD_EXAMPLES=OFF \
  -DMLX_BUILD_BENCHMARKS=OFF \
  -DMLX_BUILD_PYTHON_BINDINGS=OFF \
  -DMLX_BUILD_METAL=OFF \
  -DMLX_BUILD_CPU="$MLX_BUILD_CPU" \
  -DMLX_BUILD_CUDA="$MLX_BUILD_CUDA" \
  -DMLX_BUILD_SAFETENSORS=OFF \
  -DMLX_BUILD_GGUF=OFF \
  "${TOOLCHAIN_CMAKE_ARGS[@]}" \
  "${EXTRA_CMAKE_ARGS[@]}"

"$CMAKE_BIN" --build "$BUILD_DIR" --parallel "$BUILD_PARALLEL" --target install

printf 'Built Linux MLX install at %s (backend=%s)\n' "$INSTALL_DIR" "$MLX_BACKEND"
