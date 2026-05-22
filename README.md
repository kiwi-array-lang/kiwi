<p align="center">
  <img src="https://kiwilang.com/kiwi-icon.webp" alt="kiwi icon" width="160" height="160" />
</p>

# kiwi

`kiwi` is a tiny k-like array language implementation that can lower to `mlx` and `webgpu`.

## Get Kiwi

Download CLI binaries for macOS and Linux from
[GitHub Releases](https://github.com/kiwi-array-lang/kiwi/releases).

For Python and notebook use, install the `kiwi-array` package family. The main
package is the loader, IPython extension, and `kiwi` launcher; native payloads
live in backend wheels such as `kiwi-array-host`, `kiwi-array-metal`, and
`kiwi-array-cuda12`.

```sh
pip install kiwi-array
pip install "kiwi-array[metal,jupyter]"
pip install "kiwi-array[cuda12]"
```

Apple apps for iOS, iPadOS, macOS, and watchOS are available on the
[App Store](https://apps.apple.com/app/kiwi-programming/id6761279677).

## Try Kiwi

Try Kiwi in the browser at [kiwilang.com/repl](https://kiwilang.com/repl/).

With the CLI installed:

```sh
kiwi
kiwi path/to/file.k
```

Running `kiwi` without a file starts the local REPL.

## Jupyter

The Jupyter kernel package is owned by the workspace `extensions/jupyter-kiwi`
integration and is included in public snapshots under `extensions/jupyter-kiwi/`.
It uses the shared `libkiwi_bridge` session API and can display Vega-Lite output
emitted as JSON through Kiwi's `` `j@`` encoder.

In a fresh source checkout, bootstrap MLX first with
`KIWI_MLX_BACKEND=cpu scripts/bootstrap_deps.sh` unless `.deps/mlx` and
`.deps/mlx-c` already exist.

```sh
cd extensions/jupyter-kiwi
uv sync --managed-python --python 3.14.2 --group dev
uv run --managed-python python -m kiwi_array_jupyter_kernel.install --user
```

## Build From Source

### Requirements

- Zig on `PATH` or `ZIG_BIN` set explicitly
- CMake for MLX dependency builds
- a supported host toolchain for Zig and MLX

### Standalone Host CLI

Build the standalone host CLI:

```sh
scripts/bootstrap_duckdb.sh
zig build -Dpublic-cli=true -Druntime-backend=host -Dstrip-instrumentation=true -Doptimize=ReleaseFast
```

### MLX Backend

Bootstrap MLX and build with the native MLX backend:

```sh
KIWI_MLX_BACKEND=cpu scripts/bootstrap_deps.sh
zig build -Druntime-backend=mlx
```

`scripts/bootstrap_deps.sh` now also bootstraps a repo-local DuckDB into
`.deps/duckdb`. Host-matching builds prefer that install automatically so
DuckDB-backed CSV, Parquet, and HTTP(S) scans work without runtime extension
installation.

## Dependencies

Pinned dependency revisions live in `deps.lock.toml`.

See `THIRD_PARTY_NOTICES.md` for dependency notices.
