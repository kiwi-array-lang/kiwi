# Kiwi Python Wheels

The public Python package family is:

- `kiwilang`: Python bridge plus native Kiwi runtime payload
- `kiwilang-jupyter-kernel`: Jupyter kernel host that depends on `kiwilang`

Build local wheels from the Kiwi source root:

```sh
packaging/wheels/build_wheels.sh
```

For a quick packaging-only build using an existing `zig-out/lib`:

```sh
packaging/wheels/build_wheels.sh --skip-native-build
```

For a host-backend wheel that does not stage MLX:

```sh
KIWILANG_WHEEL_RUNTIME_BACKEND=host packaging/wheels/build_wheels.sh
```

For a Linux CUDA MLX wheel, provide an MLX prefix that contains `include/` and
`lib/libmlx.so`, build the mini bridge into that prefix, and request the CUDA
MLX backend:

```sh
MLX_INSTALL_PREFIX=/path/to/linux-x86_64-cuda-install \
  scripts/build_linux_mlxc_mini_bridge.sh "$MLX_INSTALL_PREFIX" kiwi_mlx_bridge

KIWILANG_WHEEL_RUNTIME_BACKEND=mlx \
KIWILANG_WHEEL_MLX_BACKEND=cuda \
KIWILANG_WHEEL_MLXC_MINI_BRIDGE=kiwi_mlx_bridge \
KIWI_MLX_PREFIX="$MLX_INSTALL_PREFIX" \
  packaging/wheels/build_wheels.sh
```

For hosted notebooks such as Colab or Kaggle, install the test wheel with
`--no-deps` so the wheel does not mutate the notebook image's pinned CUDA/Torch
package set. Current Colab and Kaggle GPU images use CUDA 12.8-family Python
packages; replacing those with newer NVIDIA packages can break the preinstalled
stack.

For a Colab-oriented CUDA 12.8 Linux x86_64 wheel, use the Docker wrapper:

```sh
packaging/wheels/build_colab_cuda_wheel.sh
```

The script writes the hosted-notebook wheel and its build manifest under
`out/python-wheels/` by default.

Shared hosted-notebook defaults live in `scripts/kiwi_cuda_defaults.sh`. The
wrapper uses those values for the CUDA 12.8 base image, architecture set, and
CUDA build parallelism. CUDA MLX builds default to a conservative parallel count
because the sm90 quantized kernels are memory-heavy under local Docker
emulation; override `BUILD_PARALLEL` only when intentionally tuning a specific
builder.

The CUDA MLX build uses Kiwi's hosted-notebook architecture set by default:
`70-real;75-real;80-real;89-real;90a-real`.
That covers V100 (`sm_70`), Kaggle T4 x2 / Colab T4 (`sm_75`), A100
(`sm_80`), L4 (`sm_89`), and H100/Hopper (`sm_90a`). Kaggle P100 is
`sm_60`, but current MLX CUDA kernels use CUDA features that require
`compute_70` or newer, so P100 needs the host/CPU path for now. Override
`MLX_CUDA_ARCHITECTURES` only when intentionally producing a smaller, larger,
or more specialized wheel.

`build_colab_cuda_wheel.sh` verifies the expected native payload and writes
`kiwilang-hosted-notebook-cuda-build.json` next to the direct wheel. The
manifest records the base image, architecture set, build parallelism, wheel
size, SHA-256, source commit, and whether the source tree was dirty.

The runtime wheel stages:

- `kiwilang/native/libkiwi_bridge.*`
- `kiwilang/lib/libmlx.*`
- `kiwilang/lib/libkiwi_mlx_bridge.*` when requested with `KIWILANG_WHEEL_MLXC_MINI_BRIDGE`
- `kiwilang/lib/libduckdb.*`
- `kiwilang/lib/mlx.metallib` when the MLX build provides it

The current scripts create host-platform wheels. The Colab wrapper writes a
direct hosted-notebook test wheel and leaves `auditwheel repair` off by default
because CUDA driver libraries such as `libcuda.so.1` are supplied by the hosted
runtime and should not be bundled. Set `KIWILANG_REPAIR_WHEEL=1` when explicitly
experimenting with a repaired wheel. Release automation should build the same
wheel set per platform and then run the platform repair/signing step where
needed, for example `auditwheel` from a manylinux toolchain on Linux and
`delocate` or equivalent inspection on macOS.
