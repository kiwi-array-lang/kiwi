# Kiwi Jupyter Kernel

`kiwilang-jupyter-kernel` is a Jupyter kernel for Kiwi that takes the direct-bridge
route:

- Jupyter runs a small Python `ipykernel` host
- the Python host loads the local Kiwi C ABI bridge with `ctypes`
- the bridge owns a persistent Kiwi `Session`
- the bridge and `Session` come from the Kiwi source checkout or the packaged wheel payload

This deliberately avoids the JSON REPL transport. The kernel boundary is:

```text
Jupyter
  -> ipykernel
  -> ctypes
  -> libkiwi_bridge
  -> Kiwi Session
  -> MLX
```

## What Is Here

- `build.zig`: small Zig regression target wired against [`../../src/kiwi_bridge.zig`](../../src/kiwi_bridge.zig)
- [`../../bridge/include/kiwi_bridge.h`](../../bridge/include/kiwi_bridge.h): shared C ABI for persistent Kiwi sessions
- [`../runtime/src/kiwi_bridge`](../runtime/src/kiwi_bridge): main-owned Python bridge wrapper consumed by this kernel
- `zig-src/tests.zig`: focused bridge regression tests
- `pyproject.toml`: editable Python package for the kernel host
- `src/kiwi_jupyter_kernel/binding.py`: thin re-export of the main-owned Python bridge wrapper
- `src/kiwi_jupyter_kernel/execution.py`: notebook cell execution helpers
- `src/kiwi_jupyter_kernel/kernel.py`: `ipykernel` integration
- `src/kiwi_jupyter_kernel/install.py`: bridge build plus kernelspec install helper
- `src/kiwi_jupyter_kernel/assets/kernel-logo.png`: vendored kernelspec logo source used for Jupyter icon files

## Current Scope

This first cut is intentionally narrow:

- execution is direct and stateful
- cells run line-by-line using the same blank-line and full-line-comment rules as script mode
- assignments suppress output
- echoed results surface in the notebook
- JSON strings that carry a Vega-Lite schema also surface as Vega-Lite MIME data
- completion and `inspect` cover the current built-in named functions
- delimiter-only `is_complete` distinguishes incomplete from clearly invalid input

It does not yet try to provide:

- general structured array display beyond `text/plain`
- parser-aware completeness checks
- full symbol completion from live session state
- a native Zig Jupyter wire-protocol implementation

## Build And Install

From the Kiwi repository root:

```sh
cd python/jupyter
uv python install --managed-python 3.14.2
uv sync --managed-python --python 3.14.2 --group dev
uv run --managed-python python -m kiwi_jupyter_kernel.install --user
```

In a fresh public checkout, bootstrap MLX first from the Kiwi root with
`KIWI_MLX_BACKEND=cpu scripts/bootstrap_deps.sh` unless `.deps/mlx` and
`.deps/mlx-c` already exist.

The install helper builds the official bridge in `../../zig-out/lib` if needed.
The installed library is:

- `../../zig-out/lib/libkiwi_bridge.dylib` on macOS
- `../../zig-out/lib/libkiwi_bridge.so` on Linux

The install helper writes a kernelspec that launches:

```sh
python -m kiwi_jupyter_kernel -f {connection_file}
```

When the bridge has already been built, the kernelspec also captures the
absolute `KIWI_BRIDGE_LIB` path so notebook startup does not depend on
accidentally finding the right local library at runtime.

## Tests

From this directory:

```sh
uv run --managed-python pytest tests/test_kiwi_jupyter_kernel.py
zig build test
```

From the repository root, `make test-jupyter` runs the Python Jupyter kernel
tests when that target is available.

## Notes

- The pinned dev interpreter is the uv-managed CPython `3.14.2` patch release tracked in [`.python-version`](.python-version).
- The `dev` dependency group includes the Python test stack for the kernel host plus `jupyter_kernel_test` for end-to-end kernel validation work.
- The kernelspec logo is sourced from the vendored [`src/kiwi_jupyter_kernel/assets/kernel-logo.png`](src/kiwi_jupyter_kernel/assets/kernel-logo.png), derived from the current website favicon artwork instead of depending on generated website output.
- The loader looks for packaged wheel libraries first and then `../../zig-out/lib` in source checkouts.
- Set `KIWI_BRIDGE_LIB` to override the bridge path.
- `KIWI_JUPYTER_BRIDGE_LIB` is still accepted as a compatibility alias.
- Set `KIWI_MLX_PREFIX` and `KIWI_MLX_C_INCLUDE` to override the MLX link inputs when building the bridge from Python.
- Set `KIWI_JUPYTER_DEVICE=cpu` or `gpu` to pin the default MLX device.
