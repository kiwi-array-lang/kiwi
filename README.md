<p align="center">
  <img src="https://kiwilang.com/kiwi-icon.webp" alt="kiwi icon" width="160" height="160" />
</p>

# kiwi

`kiwi` is a tiny k-like array language implementation that can lower to `mlx` and `webgpu`.

## Requirements

- Zig on `PATH` or `ZIG_BIN` set explicitly
- CMake for MLX dependency builds
- a supported host toolchain for Zig and MLX

## Quick Start

```sh
scripts/build_public_cli.sh
```

Build from source:

```sh
KIWI_MLX_BACKEND=cpu scripts/bootstrap_deps.sh
zig build
```

## Dependencies

Pinned dependency revisions live in `deps.lock.toml`.

See `THIRD_PARTY_NOTICES.md` for dependency notices.
