#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIWI_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ -f "$KIWI_ROOT/scripts/kiwi_cuda_defaults.sh" ]]; then
  WORKSPACE_ROOT="$KIWI_ROOT"
else
  WORKSPACE_ROOT="$(cd "$KIWI_ROOT/../.." && pwd)"
fi
source "$WORKSPACE_ROOT/scripts/kiwi_cuda_defaults.sh"

PLATFORM="${PLATFORM:-linux/amd64}"
BASE_IMAGE="${KIWILANG_COLAB_BASE_IMAGE:-$KIWI_CUDA_12_8_BASE_IMAGE}"
IMAGE_TAG="${KIWILANG_COLAB_IMAGE_TAG:-$KIWI_HOSTED_NOTEBOOK_CUDA_IMAGE_TAG}"
MLX_ARCH="${MLX_ARCH:-x86_64}"
MLX_SOURCE_DEPS_DIR="${MLX_SOURCE_DEPS_DIR:-$WORKSPACE_ROOT/.artifacts/mlx/linux-${MLX_ARCH}-cuda-colab128-source-deps}"
MLX_INSTALL_PREFIX="${MLX_INSTALL_PREFIX:-$WORKSPACE_ROOT/.artifacts/mlx/linux-${MLX_ARCH}-cuda-colab128-install}"
MLX_BUILD_DIR="${MLX_BUILD_DIR:-$WORKSPACE_ROOT/.artifacts/mlx/linux-${MLX_ARCH}-cuda-colab128-build}"
DUCKDB_DEPS_DIR="${DUCKDB_DEPS_DIR:-$WORKSPACE_ROOT/.artifacts/duckdb/linux-${MLX_ARCH}-cuda-colab128}"
MLX_LOCK_FILE="${MLX_LOCK_FILE:-}"
WHEEL_DIST_DIR="${KIWILANG_WHEEL_DIST_DIR:-$KIWI_ROOT/out/python-wheels/colab-cuda128}"
REPAIRED_DIST_DIR="${KIWILANG_REPAIRED_WHEEL_DIST_DIR:-$KIWI_ROOT/out/python-wheels/colab-cuda128-repaired}"
MLXC_MINI_BRIDGE_LIB="${MLXC_MINI_BRIDGE_LIB:-kiwi_mlx_bridge}"
CUDA_ARCHITECTURES="${MLX_CUDA_ARCHITECTURES:-$KIWI_HOSTED_NOTEBOOK_CUDA_ARCHITECTURES}"
BUILD_PARALLEL_VALUE="${BUILD_PARALLEL:-$KIWI_HOSTED_NOTEBOOK_CUDA_BUILD_PARALLEL}"
AUDITWHEEL_PLAT="${AUDITWHEEL_PLAT:-$KIWI_HOSTED_NOTEBOOK_CUDA_AUDITWHEEL_PLAT}"
REPAIR_WHEEL="${KIWILANG_REPAIR_WHEEL:-$KIWI_HOSTED_NOTEBOOK_CUDA_REPAIR_WHEEL}"
ALLOW_REPAIR_FAILURE="${KIWILANG_ALLOW_REPAIR_FAILURE:-$KIWI_HOSTED_NOTEBOOK_CUDA_ALLOW_REPAIR_FAILURE}"

require_single_wheel() {
  local dir="$1"
  shopt -s nullglob
  local wheels=("$dir"/kiwilang-*.whl)
  shopt -u nullglob

  if (( ${#wheels[@]} != 1 )); then
    printf 'expected one kiwilang wheel in %s, found %d\n' "$dir" "${#wheels[@]}" >&2
    exit 1
  fi

  printf '%s\n' "${wheels[0]}"
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    printf 'unable to locate shasum or sha256sum\n' >&2
    exit 1
  fi
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

DOCKER_VOLUME_ARGS=()
DOCKER_VOLUME_PATHS=()

append_docker_volume_for_path() {
  local path="$1"
  local mount_path
  local existing

  [[ -n "$path" ]] || return 0
  mount_path="$path"
  if [[ -f "$mount_path" ]]; then
    mount_path="$(dirname "$mount_path")"
  fi
  while [[ ! -d "$mount_path" && "$mount_path" != "/" ]]; do
    mount_path="$(dirname "$mount_path")"
  done
  [[ -d "$mount_path" && "$mount_path" != "/" ]] || return 0
  mount_path="$(cd "$mount_path" && pwd)"

  if (( ${#DOCKER_VOLUME_PATHS[@]} > 0 )); then
    for existing in "${DOCKER_VOLUME_PATHS[@]}"; do
      case "$mount_path/" in
        "$existing"/*) return 0 ;;
      esac
    done
  fi

  DOCKER_VOLUME_PATHS+=("$mount_path")
  DOCKER_VOLUME_ARGS+=("-v" "$mount_path:$mount_path")
}

prepare_docker_volume_args() {
  DOCKER_VOLUME_ARGS=()
  DOCKER_VOLUME_PATHS=()
  append_docker_volume_for_path "$WORKSPACE_ROOT"
  append_docker_volume_for_path "$MLX_SOURCE_DEPS_DIR"
  append_docker_volume_for_path "$MLX_INSTALL_PREFIX"
  append_docker_volume_for_path "$MLX_BUILD_DIR"
  append_docker_volume_for_path "$DUCKDB_DEPS_DIR"
  append_docker_volume_for_path "$WHEEL_DIST_DIR"
  append_docker_volume_for_path "$REPAIRED_DIST_DIR"
}

verify_wheel_payload() {
  local wheel="$1"
  local entry
  local listing
  local required_entries=(
    "kiwilang/notebook.py"
    "kiwilang/lib/libduckdb.so"
    "kiwilang/lib/libkiwi_mlx_bridge.so"
    "kiwilang/lib/libmlx.so"
    "kiwilang/native/libkiwi_bridge.so"
  )

  listing="$(mktemp)"
  unzip -l "$wheel" > "$listing"

  for entry in "${required_entries[@]}"; do
    if ! grep -Fq "$entry" "$listing"; then
      rm -f "$listing"
      printf 'wheel payload check failed: missing %s in %s\n' "$entry" "$wheel" >&2
      exit 1
    fi
  done

  rm -f "$listing"
}

write_build_manifest() {
  local wheel="$1"
  local manifest="$WHEEL_DIST_DIR/kiwilang-hosted-notebook-cuda-build.json"
  local source_commit="unknown"
  local source_state="unknown"

  if git -C "$WORKSPACE_ROOT" rev-parse --short HEAD >/dev/null 2>&1; then
    source_commit="$(git -C "$WORKSPACE_ROOT" rev-parse --short HEAD)"
    if [[ -z "$(git -C "$WORKSPACE_ROOT" status --porcelain)" ]]; then
      source_state="clean"
    else
      source_state="dirty"
    fi
  fi

  {
    printf '{\n'
    printf '  "wheel": "%s",\n' "$(json_escape "$(basename "$wheel")")"
    printf '  "sha256": "%s",\n' "$(sha256_file "$wheel")"
    printf '  "bytes": %s,\n' "$(wc -c < "$wheel" | tr -d '[:space:]')"
    printf '  "platform": "%s",\n' "$(json_escape "$PLATFORM")"
    printf '  "base_image": "%s",\n' "$(json_escape "$BASE_IMAGE")"
    printf '  "image_tag": "%s",\n' "$(json_escape "$IMAGE_TAG")"
    printf '  "mlx_backend": "cuda",\n'
    printf '  "mlx_cuda_architectures": "%s",\n' "$(json_escape "$CUDA_ARCHITECTURES")"
    printf '  "build_parallel": %s,\n' "$BUILD_PARALLEL_VALUE"
    printf '  "repair_wheel": "%s",\n' "$(json_escape "$REPAIR_WHEEL")"
    printf '  "auditwheel_plat": "%s",\n' "$(json_escape "$AUDITWHEEL_PLAT")"
    printf '  "source_commit": "%s",\n' "$(json_escape "$source_commit")"
    printf '  "source_state": "%s",\n' "$(json_escape "$source_state")"
    printf '  "generated_at_utc": "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '}\n'
  } > "$manifest"

  printf '%s\n' "$manifest"
}

case "$PLATFORM" in
  linux/amd64) ;;
  *)
    printf 'Colab CUDA wheels are currently built for linux/amd64, got %s\n' "$PLATFORM" >&2
    exit 2
    ;;
esac

if ! docker info >/dev/null 2>&1; then
  if [[ "$(uname -s)" == "Darwin" ]] && command -v orb >/dev/null 2>&1; then
    orb start >/dev/null 2>&1 || true
  fi
fi

if ! docker info >/dev/null 2>&1; then
  printf 'docker is not available; start OrbStack or another Docker engine first\n' >&2
  exit 1
fi

if [[ -z "$MLX_LOCK_FILE" && -f "$KIWI_ROOT/deps.public.lock.toml" ]]; then
  MLX_LOCK_FILE="$KIWI_ROOT/deps.public.lock.toml"
elif [[ -z "$MLX_LOCK_FILE" && -f "$KIWI_ROOT/deps.lock.toml" ]]; then
  MLX_LOCK_FILE="$KIWI_ROOT/deps.lock.toml"
fi

docker build \
  --platform "$PLATFORM" \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  -t "$IMAGE_TAG" \
  -f "$WORKSPACE_ROOT/scripts/kiwi-zig-linux-builder.Dockerfile" \
  "$WORKSPACE_ROOT"

mkdir -p "$WHEEL_DIST_DIR" "$REPAIRED_DIST_DIR"
if [[ "$REPAIR_WHEEL" == "0" ]]; then
  rm -f "$REPAIRED_DIST_DIR"/kiwilang-*.whl
fi
prepare_docker_volume_args

docker run \
  --rm \
  --platform "$PLATFORM" \
  --user "$(id -u):$(id -g)" \
  -e DEVELOPER_DIR=/tmp \
  -e HOME=/tmp \
  -e BUILD_PARALLEL="$BUILD_PARALLEL_VALUE" \
  -e DUCKDB_DEPS_DIR="$DUCKDB_DEPS_DIR" \
  -e KIWI_ZIG_REAL=/usr/local/bin/zig \
  -e KIWI_DUCKDB_PLATFORM=linux-x86_64 \
  -e KIWILANG_ALLOW_REPAIR_FAILURE="$ALLOW_REPAIR_FAILURE" \
  -e KIWILANG_REPAIR_WHEEL="$REPAIR_WHEEL" \
  -e KIWILANG_REPAIRED_WHEEL_DIST_DIR="$REPAIRED_DIST_DIR" \
  -e KIWILANG_WHEEL_BUILD_JUPYTER=0 \
  -e KIWILANG_WHEEL_DIST_DIR="$WHEEL_DIST_DIR" \
  -e KIWILANG_WHEEL_MLX_BACKEND=cuda \
  -e KIWILANG_WHEEL_MLXC_MINI_BRIDGE="$MLXC_MINI_BRIDGE_LIB" \
  -e KIWILANG_WHEEL_RUNTIME_BACKEND=mlx \
  -e KIWI_SOURCE_ROOT="$KIWI_ROOT" \
  -e KIWI_DUCKDB_PREFIX="$DUCKDB_DEPS_DIR/duckdb" \
  -e KIWI_MLX_C_INCLUDE="$MLX_SOURCE_DEPS_DIR/mlx-c" \
  -e KIWI_MLX_SOURCE_DEPS_DIR="$MLX_SOURCE_DEPS_DIR" \
  -e KIWI_MLX_PREFIX="$MLX_INSTALL_PREFIX" \
  -e KIWI_PUBLIC_LOCK_FILE="$MLX_LOCK_FILE" \
  -e MLX_BACKEND=cuda \
  -e MLX_BUILD_DIR="$MLX_BUILD_DIR" \
  -e MLX_C_INCLUDE_ROOT="$MLX_SOURCE_DEPS_DIR/mlx-c" \
  -e MLX_CUDA_ARCHITECTURES="$CUDA_ARCHITECTURES" \
  -e MLX_INSTALL_PREFIX="$MLX_INSTALL_PREFIX" \
  -e MLX_SRC_DIR="$MLX_SOURCE_DEPS_DIR/src/mlx" \
  -e MLXC_MINI_BRIDGE_LIB="$MLXC_MINI_BRIDGE_LIB" \
  -e AUDITWHEEL_PLAT="$AUDITWHEEL_PLAT" \
  -e UV_PROJECT_ENVIRONMENT=/tmp/kiwilang-colab-uv \
  "${DOCKER_VOLUME_ARGS[@]}" \
  -w "$WORKSPACE_ROOT" \
  "$IMAGE_TAG" \
  bash -lc '
    set -euo pipefail
    export LD_LIBRARY_PATH="$MLX_INSTALL_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [[ ! -d "$MLX_SRC_DIR" || ! -d "$MLX_C_INCLUDE_ROOT/mlx" ]]; then
      bootstrap_args=(--fetch-only)
      if [[ -n "$KIWI_PUBLIC_LOCK_FILE" ]]; then
        bootstrap_args+=(--lock-file "$KIWI_PUBLIC_LOCK_FILE")
      fi
      KIWI_DEPS_DIR="$KIWI_MLX_SOURCE_DEPS_DIR" \
        bash "$KIWI_SOURCE_ROOT/scripts/bootstrap_deps.sh" "${bootstrap_args[@]}"
    fi
    scripts/build_linux_mlx.sh
    bash scripts/build_linux_mlxc_mini_bridge.sh "$MLX_INSTALL_PREFIX" "$MLXC_MINI_BRIDGE_LIB"
    KIWI_DEPS_DIR="$DUCKDB_DEPS_DIR" bash "$KIWI_SOURCE_ROOT/scripts/bootstrap_duckdb.sh"
    cd "$KIWI_SOURCE_ROOT"
    packaging/wheels/build_wheels.sh
    if [[ "$KIWILANG_REPAIR_WHEEL" != "0" ]]; then
      shopt -s nullglob
      wheels=("$KIWILANG_WHEEL_DIST_DIR"/kiwilang-*.whl)
      if (( ${#wheels[@]} != 1 )); then
        printf "expected one kiwilang wheel, found %d\n" "${#wheels[@]}" >&2
        exit 1
      fi
      repair_tmp="$(mktemp -d)"
      rm -f "$KIWILANG_REPAIRED_WHEEL_DIST_DIR"/kiwilang-*.whl
      if uvx --from auditwheel auditwheel repair --plat "$AUDITWHEEL_PLAT" -w "$repair_tmp" "${wheels[0]}"; then
        mv "$repair_tmp"/kiwilang-*.whl "$KIWILANG_REPAIRED_WHEEL_DIST_DIR"/
        rmdir "$repair_tmp"
      else
        rm -rf "$repair_tmp"
        if [[ "$KIWILANG_ALLOW_REPAIR_FAILURE" == "1" ]]; then
          printf "auditwheel repair failed; direct Colab test wheel remains at %s\n" "${wheels[0]}" >&2
        else
          exit 1
        fi
      fi
    fi
  '

wheel="$(require_single_wheel "$WHEEL_DIST_DIR")"
verify_wheel_payload "$wheel"
manifest="$(write_build_manifest "$wheel")"

printf 'Colab CUDA wheel output: %s\n' "$WHEEL_DIST_DIR"
printf 'Colab CUDA wheel: %s\n' "$wheel"
printf 'Colab CUDA wheel manifest: %s\n' "$manifest"
if [[ "$REPAIR_WHEEL" != "0" ]]; then
  printf 'Repaired wheel output: %s\n' "$REPAIRED_DIST_DIR"
fi
