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
SRC_DIR="$DEPS_DIR/src"
LOCK_FILE="deps.lock.toml"
FETCH_ONLY=0
LINK_LOCAL=0
MLX_PREFIX=""
MLX_C_INCLUDE=""
BOOTSTRAP_CMAKE_BIN=""
BOOTSTRAP_BUILD_PARALLEL=""

usage() {
  cat >&2 <<EOF
usage:
  ${BASH_SOURCE[0]} [--lock-file <path>] [--fetch-only]
  ${BASH_SOURCE[0]} --link-local --mlx-prefix <path> --mlx-c-include <path>

default behavior:
  - fetch the locked mlx and mlx-c sources into .deps/src
  - apply any checked-in overlay patches from the lock file
  - bootstrap DuckDB into .deps/duckdb with linked parquet/http support
  - build MLX into .deps/mlx
  - expose MLX C headers at .deps/mlx-c

environment:
  - KIWI_MLX_BACKEND=cpu|metal (default: metal on macOS, cpu on Linux)
  - KIWI_MLX_LINKAGE=shared|static (default: shared)
  - KIWI_MLX_METAL_KERNEL_PROFILE=default|kiwi_minimal|kiwi_core
    (default: default; `kiwi_minimal` and `kiwi_core` are experimental
    size-reduction profiles)
  - KIWI_DEPS_DIR=<path> (default: .deps under kiwi-zig-main)
  - KIWI_DUCKDB_VERSION=<version> (default: 1.5.1)
  - KIWI_DUCKDB_URL=<asset-url> (override the default release asset)
EOF
  exit 1
}

absolute_dir() {
  local path="$1"
  (
    cd "$path"
    pwd
  )
}

resolve_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$ROOT/$path"
  fi
}

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

default_parallelism() {
  if [[ -n "${BUILD_PARALLEL:-}" ]]; then
    printf '%s\n' "$BUILD_PARALLEL"
    return
  fi

  if command -v nproc >/dev/null 2>&1; then
    nproc
    return
  fi

  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
    return
  fi

  printf '4\n'
}

repo_checkout_name() {
  case "$1" in
    mlx) printf 'mlx\n' ;;
    mlx_c) printf 'mlx-c\n' ;;
    *)
      printf 'unsupported dependency key in lock file: %s\n' "$1" >&2
      exit 1
      ;;
  esac
}

read_lock_string() {
  local repo_key="$1"
  local field="$2"
  awk -v section="repos.${repo_key}" -v field="$field" '
    $0 == "[" section "]" { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && $1 == field {
      line = $0
      sub(/^[^=]*=[[:space:]]*"/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "$LOCK_FILE"
}

read_lock_patches() {
  local repo_key="$1"
  awk -v section="repos.${repo_key}" '
    $0 == "[" section "]" { in_section = 1; next }
    /^\[/ {
      in_section = 0
      in_patches = 0
    }
    !in_section { next }
    in_patches {
      if ($0 ~ /\]/) {
        in_patches = 0
        next
      }
      if (match($0, /"([^"]+)"/)) {
        line = substr($0, RSTART + 1, RLENGTH - 2)
        print line
      }
      next
    }
    $1 == "patches" && $0 ~ /\[/ {
      in_patches = 1
      if (match($0, /"([^"]+)"/)) {
        line = substr($0, RSTART + 1, RLENGTH - 2)
        print line
      }
    }
  ' "$LOCK_FILE"
}

link_dep() {
  local name="$1"
  local source_dir="$2"
  local target="$DEPS_DIR/$name"
  rm -rf "$target"
  ln -s "$source_dir" "$target"
}

sync_locked_repo() {
  local repo_key="$1"
  local checkout_name
  local repo_dir
  local remote_url
  local rev
  local current_url

  checkout_name="$(repo_checkout_name "$repo_key")"
  repo_dir="$SRC_DIR/$checkout_name"
  remote_url="$(read_lock_string "$repo_key" url)"
  rev="$(read_lock_string "$repo_key" rev)"

  mkdir -p "$SRC_DIR"
  if [[ ! -d "$repo_dir/.git" ]]; then
    rm -rf "$repo_dir"
    git init "$repo_dir" >/dev/null
    git -C "$repo_dir" remote add origin "$remote_url"
  else
    current_url="$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$current_url" ]]; then
      git -C "$repo_dir" remote add origin "$remote_url"
    elif [[ "$current_url" != "$remote_url" ]]; then
      git -C "$repo_dir" remote set-url origin "$remote_url"
    fi
  fi

  git -C "$repo_dir" fetch --force --tags origin "$rev" >/dev/null
  git -C "$repo_dir" checkout --detach FETCH_HEAD >/dev/null
  git -C "$repo_dir" reset --hard FETCH_HEAD >/dev/null
  git -C "$repo_dir" clean -fdx >/dev/null

  while IFS= read -r patch_path; do
    [[ -n "$patch_path" ]] || continue
    git -C "$repo_dir" apply --whitespace=nowarn "$(resolve_path "$patch_path")"
    printf 'applied %s to %s\n' "$patch_path" "$checkout_name"
  done < <(read_lock_patches "$repo_key")

  printf 'synced %s at %s\n' "$checkout_name" "$rev"
}

stage_mlx_c_headers() {
  local source_dir="$SRC_DIR/mlx-c"
  [[ -d "$source_dir" ]] || { printf 'missing mlx-c checkout at %s\n' "$source_dir" >&2; exit 1; }
  mkdir -p "$DEPS_DIR"
  link_dep "mlx-c" "$source_dir"
  printf 'bootstrapped %s/mlx-c -> %s\n' "$DEPS_DIR" "$source_dir"
}

build_mlx() {
  local build_dir="$DEPS_DIR/build/mlx"
  local install_dir="$DEPS_DIR/mlx"
  local fetchcontent_dir="$DEPS_DIR/fetchcontent"
  local host_os
  local backend
  local linkage
  local macos_deployment_target
  local metal_kernel_profile
  local -a cmake_args

  host_os="$(uname -s)"
  backend="${KIWI_MLX_BACKEND:-}"
  linkage="${KIWI_MLX_LINKAGE:-shared}"
  macos_deployment_target="${KIWI_MLX_MACOS_DEPLOYMENT_TARGET:-}"
  metal_kernel_profile="${KIWI_MLX_METAL_KERNEL_PROFILE:-default}"

  rm -rf "$build_dir" "$install_dir"
  mkdir -p "$DEPS_DIR/build" "$fetchcontent_dir"

  case "$linkage" in
    shared)
      ;;
    static)
      ;;
    *)
      printf 'unsupported KIWI_MLX_LINKAGE: %s\nexpected shared or static\n' "$linkage" >&2
      exit 1
      ;;
  esac

  cmake_args=(
    -S "$SRC_DIR/mlx"
    -B "$build_dir"
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="$install_dir"
    -DFETCHCONTENT_BASE_DIR="$fetchcontent_dir"
    "-DBUILD_SHARED_LIBS=$( [[ "$linkage" = shared ]] && printf 'ON' || printf 'OFF' )"
    -DMLX_BUILD_TESTS=OFF
    -DMLX_BUILD_EXAMPLES=OFF
    -DMLX_BUILD_BENCHMARKS=OFF
    -DMLX_BUILD_PYTHON_BINDINGS=OFF
    -DMLX_BUILD_SAFETENSORS=ON
    -DMLX_BUILD_GGUF=OFF
  )

  case "$host_os" in
    Darwin)
      backend="${backend:-metal}"
      if [[ -n "$macos_deployment_target" ]]; then
        cmake_args+=("-DCMAKE_OSX_DEPLOYMENT_TARGET=$macos_deployment_target")
      fi
      case "$backend" in
        metal)
          cmake_args+=(
            -DMLX_BUILD_CPU=ON
            -DMLX_BUILD_METAL=ON
            -DMLX_BUILD_CUDA=OFF
            -DMLX_METAL_JIT=OFF
            "-DMLX_METAL_KERNEL_PROFILE=$metal_kernel_profile"
          )
          ;;
        cpu)
          cmake_args+=(
            -DMLX_BUILD_CPU=ON
            -DMLX_BUILD_METAL=OFF
            -DMLX_BUILD_CUDA=OFF
          )
          ;;
        *)
          printf 'unsupported KIWI_MLX_BACKEND for macOS: %s\nexpected metal or cpu\n' "$backend" >&2
          exit 1
          ;;
      esac
      ;;
    Linux)
      backend="${backend:-cpu}"
      case "$backend" in
        cpu)
          cmake_args+=(
            -DMLX_BUILD_CPU=ON
            -DMLX_BUILD_METAL=OFF
            -DMLX_BUILD_CUDA=OFF
          )
          ;;
        cuda)
          cmake_args+=(
            -DMLX_BUILD_CPU=ON
            -DMLX_BUILD_METAL=OFF
            -DMLX_BUILD_CUDA=ON
          )
          if [[ -n "${MLX_CUDA_ARCHITECTURES:-}" ]]; then
            cmake_args+=("-DMLX_CUDA_ARCHITECTURES=$MLX_CUDA_ARCHITECTURES")
          fi
          ;;
        *)
          printf 'unsupported KIWI_MLX_BACKEND for Linux: %s\nexpected cpu or cuda\n' "$backend" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      printf 'unsupported host OS for MLX bootstrap: %s\n' "$host_os" >&2
      exit 1
      ;;
  esac

  "$BOOTSTRAP_CMAKE_BIN" "${cmake_args[@]}"
  "$BOOTSTRAP_CMAKE_BIN" --build "$build_dir" --parallel "$BOOTSTRAP_BUILD_PARALLEL" --target install
  cat > "$install_dir/.kiwi-build-config" <<EOF
host_os=$host_os
backend=$backend
linkage=$linkage
metal_kernel_profile=$metal_kernel_profile
macos_deployment_target=$macos_deployment_target
EOF
  printf 'built MLX install at %s\n' "$install_dir"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lock-file)
      [[ $# -ge 2 ]] || usage
      LOCK_FILE="$2"
      shift 2
      ;;
    --fetch-only)
      FETCH_ONLY=1
      shift
      ;;
    --link-local)
      LINK_LOCAL=1
      shift
      ;;
    --mlx-prefix)
      [[ $# -ge 2 ]] || usage
      MLX_PREFIX="$2"
      shift 2
      ;;
    --mlx-c-include)
      [[ $# -ge 2 ]] || usage
      MLX_C_INCLUDE="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

LOCK_FILE="$(resolve_path "$LOCK_FILE")"

if [[ "$LINK_LOCAL" -eq 1 ]]; then
  [[ -n "$MLX_PREFIX" && -n "$MLX_C_INCLUDE" ]] || usage
  [[ -d "$MLX_PREFIX" ]] || { printf 'missing mlx prefix: %s\n' "$MLX_PREFIX" >&2; exit 1; }
  [[ -d "$MLX_C_INCLUDE" ]] || { printf 'missing mlx-c include dir: %s\n' "$MLX_C_INCLUDE" >&2; exit 1; }

  mkdir -p "$DEPS_DIR"
  link_dep "mlx" "$(absolute_dir "$MLX_PREFIX")"
  link_dep "mlx-c" "$(absolute_dir "$MLX_C_INCLUDE")"

  printf 'bootstrapped %s/mlx -> %s\n' "$DEPS_DIR" "$(absolute_dir "$MLX_PREFIX")"
  printf 'bootstrapped %s/mlx-c -> %s\n' "$DEPS_DIR" "$(absolute_dir "$MLX_C_INCLUDE")"
  KIWI_DEPS_DIR="$DEPS_DIR" bash "$ROOT/scripts/bootstrap_duckdb.sh"
  exit 0
fi

[[ -f "$LOCK_FILE" ]] || { printf 'missing dependency lock file: %s\n' "$LOCK_FILE" >&2; exit 1; }

sync_locked_repo "mlx"
sync_locked_repo "mlx_c"
stage_mlx_c_headers
KIWI_DEPS_DIR="$DEPS_DIR" bash "$ROOT/scripts/bootstrap_duckdb.sh"

if [[ "$FETCH_ONLY" -eq 0 ]]; then
  BOOTSTRAP_CMAKE_BIN="$(find_cmake)"
  BOOTSTRAP_BUILD_PARALLEL="$(default_parallelism)"
  build_mlx
fi
