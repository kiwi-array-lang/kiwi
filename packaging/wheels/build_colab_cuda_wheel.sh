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
BASE_IMAGE="${KIWI_ARRAY_COLAB_BASE_IMAGE:-$KIWI_CUDA_12_8_BASE_IMAGE}"
IMAGE_TAG="${KIWI_ARRAY_COLAB_IMAGE_TAG:-$KIWI_HOSTED_NOTEBOOK_CUDA_IMAGE_TAG}"
MLX_ARCH="${MLX_ARCH:-x86_64}"
CACHE_LABEL="${KIWI_ARRAY_COLAB_CACHE_LABEL:-cuda-colab128}"
MLX_SOURCE_DEPS_DIR="${MLX_SOURCE_DEPS_DIR:-$WORKSPACE_ROOT/.artifacts/mlx/linux-${MLX_ARCH}-${CACHE_LABEL}-source-deps}"
MLX_INSTALL_PREFIX="${MLX_INSTALL_PREFIX:-$WORKSPACE_ROOT/.artifacts/mlx/linux-${MLX_ARCH}-${CACHE_LABEL}-install}"
MLX_BUILD_DIR="${MLX_BUILD_DIR:-$WORKSPACE_ROOT/.artifacts/mlx/linux-${MLX_ARCH}-${CACHE_LABEL}-build}"
DUCKDB_DEPS_DIR="${DUCKDB_DEPS_DIR:-$WORKSPACE_ROOT/.artifacts/duckdb/linux-${MLX_ARCH}-${CACHE_LABEL}}"
MLX_LOCK_FILE="${MLX_LOCK_FILE:-}"
WHEEL_DIST_DIR="${KIWI_ARRAY_WHEEL_DIST_DIR:-$KIWI_ROOT/out/python-wheels/colab-cuda128}"
REPAIRED_DIST_DIR="${KIWI_ARRAY_REPAIRED_WHEEL_DIST_DIR:-$KIWI_ROOT/out/python-wheels/colab-cuda128-repaired}"
MLXC_MINI_BRIDGE_LIB="${MLXC_MINI_BRIDGE_LIB:-kiwi_mlx_bridge}"
CUDA_ARCHITECTURES="${MLX_CUDA_ARCHITECTURES:-$KIWI_HOSTED_NOTEBOOK_CUDA_ARCHITECTURES}"
CUDA_KERNEL_PROFILE="${KIWI_MLX_CUDA_KERNEL_PROFILE:-${MLX_CUDA_KERNEL_PROFILE:-$KIWI_HOSTED_NOTEBOOK_CUDA_KERNEL_PROFILE}}"
BUILD_PARALLEL_VALUE="${BUILD_PARALLEL:-$KIWI_HOSTED_NOTEBOOK_CUDA_BUILD_PARALLEL}"
AUDITWHEEL_PLAT="${AUDITWHEEL_PLAT:-$KIWI_HOSTED_NOTEBOOK_CUDA_AUDITWHEEL_PLAT}"
DEFAULT_AUDITWHEEL_EXCLUDES="libcuda.so.1 libcublasLt.so.12 libcudnn.so.9 libcudnn_adv.so.9 libcudnn_cnn.so.9 libcudnn_engines_precompiled.so.9 libcudnn_engines_runtime_compiled.so.9 libcudnn_graph.so.9 libcudnn_heuristic.so.9 libcudnn_ops.so.9 libnccl.so.2 libnvrtc.so.12"
AUDITWHEEL_EXCLUDES="${KIWI_ARRAY_AUDITWHEEL_EXCLUDES:-$DEFAULT_AUDITWHEEL_EXCLUDES}"
REPAIR_WHEEL="${KIWI_ARRAY_REPAIR_WHEEL:-$KIWI_HOSTED_NOTEBOOK_CUDA_REPAIR_WHEEL}"
ALLOW_REPAIR_FAILURE="${KIWI_ARRAY_ALLOW_REPAIR_FAILURE:-$KIWI_HOSTED_NOTEBOOK_CUDA_ALLOW_REPAIR_FAILURE}"

require_single_wheel() {
  local dir="$1"
  shopt -s nullglob
  local wheels=("$dir"/kiwi_array_cuda12-*.whl)
  shopt -u nullglob

  if (( ${#wheels[@]} != 1 )); then
    printf 'expected one kiwi-array-cuda12 wheel in %s, found %d\n' "$dir" "${#wheels[@]}" >&2
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

sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    printf 'unable to locate shasum or sha256sum\n' >&2
    exit 1
  fi
}

source_deps_cache_key() {
  {
    if [[ -n "$MLX_LOCK_FILE" && -f "$MLX_LOCK_FILE" ]]; then
      printf 'lock:%s:%s\n' "$MLX_LOCK_FILE" "$(sha256_file "$MLX_LOCK_FILE")"
    fi
    if [[ -d "$KIWI_ROOT/deps/patches/mlx" ]]; then
      find "$KIWI_ROOT/deps/patches/mlx" -type f -name '*.patch' -print | sort | while IFS= read -r patch; do
        printf 'patch:%s:%s\n' "${patch#$KIWI_ROOT/}" "$(sha256_file "$patch")"
      done
    fi
  } | sha256_stream
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
    "kiwi_array_cuda12/lib/libduckdb.so"
    "kiwi_array_cuda12/lib/libkiwi_mlx_bridge.so"
    "kiwi_array_cuda12/lib/libmlx.so"
    "kiwi_array_cuda12/bin/kiwi"
    "kiwi_array_cuda12/native/libkiwi_bridge.so"
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
  local manifest="$WHEEL_DIST_DIR/kiwi-array-cuda12-hosted-notebook-cuda-build.json"
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
    printf '  "mlx_cuda_kernel_profile": "%s",\n' "$(json_escape "$CUDA_KERNEL_PROFILE")"
    printf '  "build_parallel": %s,\n' "$BUILD_PARALLEL_VALUE"
    printf '  "repair_wheel": "%s",\n' "$(json_escape "$REPAIR_WHEEL")"
    printf '  "auditwheel_plat": "%s",\n' "$(json_escape "$AUDITWHEEL_PLAT")"
    printf '  "auditwheel_excludes": "%s",\n' "$(json_escape "$AUDITWHEEL_EXCLUDES")"
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

SOURCE_DEPS_CACHE_KEY="$(source_deps_cache_key)"

docker build \
  --platform "$PLATFORM" \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  -t "$IMAGE_TAG" \
  -f "$WORKSPACE_ROOT/scripts/kiwi-zig-linux-builder.Dockerfile" \
  "$WORKSPACE_ROOT"

mkdir -p "$WHEEL_DIST_DIR" "$REPAIRED_DIST_DIR"
if [[ "$REPAIR_WHEEL" == "0" ]]; then
  rm -f "$REPAIRED_DIST_DIR"/kiwi_array_cuda12-*.whl
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
  -e KIWI_ARRAY_ALLOW_REPAIR_FAILURE="$ALLOW_REPAIR_FAILURE" \
  -e KIWI_ARRAY_REPAIR_WHEEL="$REPAIR_WHEEL" \
  -e KIWI_ARRAY_REPAIRED_WHEEL_DIST_DIR="$REPAIRED_DIST_DIR" \
  -e KIWI_ARRAY_WHEEL_BUILD_JUPYTER=0 \
  -e KIWI_ARRAY_WHEEL_DIST_DIR="$WHEEL_DIST_DIR" \
  -e KIWI_ARRAY_WHEEL_MLX_BACKEND=cuda \
  -e KIWI_ARRAY_WHEEL_MLXC_MINI_BRIDGE="$MLXC_MINI_BRIDGE_LIB" \
  -e KIWI_ARRAY_WHEEL_RUNTIME_BACKEND=mlx \
  -e KIWI_ARRAY_WHEEL_RUNTIME_PACKAGE=cuda12 \
  -e KIWI_SOURCE_ROOT="$KIWI_ROOT" \
  -e KIWI_DUCKDB_PREFIX="$DUCKDB_DEPS_DIR/duckdb" \
  -e KIWI_MLX_C_INCLUDE="$MLX_SOURCE_DEPS_DIR/mlx-c" \
  -e KIWI_MLX_SOURCE_DEPS_DIR="$MLX_SOURCE_DEPS_DIR" \
  -e KIWI_MLX_PREFIX="$MLX_INSTALL_PREFIX" \
  -e KIWI_MLX_SOURCE_DEPS_CACHE_KEY="$SOURCE_DEPS_CACHE_KEY" \
  -e KIWI_PUBLIC_LOCK_FILE="$MLX_LOCK_FILE" \
  -e KIWI_CUDA_DISABLE_SM80_QMM="$KIWI_CUDA_DISABLE_SM80_QMM" \
  -e KIWI_MLX_CUDA_KERNEL_PROFILE="$CUDA_KERNEL_PROFILE" \
  -e MLX_BACKEND=cuda \
  -e MLX_BUILD_DIR="$MLX_BUILD_DIR" \
  -e MLX_C_INCLUDE_ROOT="$MLX_SOURCE_DEPS_DIR/mlx-c" \
  -e MLX_CUDA_ARCHITECTURES="$CUDA_ARCHITECTURES" \
  -e MLX_CUDA_KERNEL_PROFILE="$CUDA_KERNEL_PROFILE" \
  -e MLX_INSTALL_PREFIX="$MLX_INSTALL_PREFIX" \
  -e MLX_SRC_DIR="$MLX_SOURCE_DEPS_DIR/src/mlx" \
  -e MLXC_MINI_BRIDGE_LIB="$MLXC_MINI_BRIDGE_LIB" \
  -e AUDITWHEEL_PLAT="$AUDITWHEEL_PLAT" \
  -e AUDITWHEEL_EXCLUDES="$AUDITWHEEL_EXCLUDES" \
  -e UV_PROJECT_ENVIRONMENT=/tmp/kiwi-array-colab-uv \
  "${DOCKER_VOLUME_ARGS[@]}" \
  -w "$WORKSPACE_ROOT" \
  "$IMAGE_TAG" \
  bash -lc '
    set -euo pipefail
    export LD_LIBRARY_PATH="$MLX_INSTALL_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    source_cache_stamp="$KIWI_MLX_SOURCE_DEPS_DIR/.kiwi-source-cache-key"
    current_source_cache_key=""
    if [[ -f "$source_cache_stamp" ]]; then
      current_source_cache_key="$(cat "$source_cache_stamp")"
    fi
    if [[ ! -d "$MLX_SRC_DIR" || ! -d "$MLX_C_INCLUDE_ROOT/mlx" || "$current_source_cache_key" != "$KIWI_MLX_SOURCE_DEPS_CACHE_KEY" ]]; then
      bootstrap_args=(--fetch-only)
      if [[ -n "$KIWI_PUBLIC_LOCK_FILE" ]]; then
        bootstrap_args+=(--lock-file "$KIWI_PUBLIC_LOCK_FILE")
      fi
      KIWI_DEPS_DIR="$KIWI_MLX_SOURCE_DEPS_DIR" \
        bash "$KIWI_SOURCE_ROOT/scripts/bootstrap_deps.sh" "${bootstrap_args[@]}"
      printf "%s\n" "$KIWI_MLX_SOURCE_DEPS_CACHE_KEY" > "$source_cache_stamp"
    fi
    scripts/build_linux_mlx.sh
    bash scripts/build_linux_mlxc_mini_bridge.sh "$MLX_INSTALL_PREFIX" "$MLXC_MINI_BRIDGE_LIB"
    KIWI_DEPS_DIR="$DUCKDB_DEPS_DIR" bash "$KIWI_SOURCE_ROOT/scripts/bootstrap_duckdb.sh"
    cd "$KIWI_SOURCE_ROOT"
    packaging/wheels/build_wheels.sh
    if [[ "$KIWI_ARRAY_REPAIR_WHEEL" != "0" ]]; then
      shopt -s nullglob
      wheels=("$KIWI_ARRAY_WHEEL_DIST_DIR"/kiwi_array_cuda12-*.whl)
      if (( ${#wheels[@]} != 1 )); then
        printf "expected one kiwi-array-cuda12 wheel, found %d\n" "${#wheels[@]}" >&2
        exit 1
      fi
      repair_tmp="$(mktemp -d)"
      rm -f "$KIWI_ARRAY_REPAIRED_WHEEL_DIST_DIR"/kiwi_array_cuda12-*.whl
      repair_args=(--plat "$AUDITWHEEL_PLAT" -w "$repair_tmp")
      if [[ -n "$AUDITWHEEL_EXCLUDES" ]]; then
        for exclude in $AUDITWHEEL_EXCLUDES; do
          repair_args+=(--exclude "$exclude")
        done
      fi
      if uvx --from auditwheel auditwheel repair "${repair_args[@]}" "${wheels[0]}"; then
        mv "$repair_tmp"/kiwi_array_cuda12-*.whl "$KIWI_ARRAY_REPAIRED_WHEEL_DIST_DIR"/
        rmdir "$repair_tmp"
      else
        rm -rf "$repair_tmp"
        if [[ "$KIWI_ARRAY_ALLOW_REPAIR_FAILURE" == "1" ]]; then
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
