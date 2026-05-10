#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
from pathlib import Path


KIWI_ROOT = Path(__file__).resolve().parents[2]


def default_workspace_root() -> Path:
    if (KIWI_ROOT / "scripts" / "kiwi_cuda_defaults.sh").exists():
        return KIWI_ROOT
    if len(KIWI_ROOT.parents) > 1:
        return KIWI_ROOT.parents[1]
    return KIWI_ROOT


WORKSPACE_ROOT = default_workspace_root()
RUNTIME_PACKAGE = KIWI_ROOT / "python" / "runtime" / "src" / "kiwilang"
LINUX_TOOLCHAIN_RUNTIME_NAMES = {
    "libgcc_s.so.1",
    "libstdc++.so.6",
}
LINUX_MLX_CUDA_RPATH = ":".join(
    [
        "$ORIGIN",
        "$ORIGIN/../../nvidia/cublas/lib",
        "$ORIGIN/../../nvidia/cuda_nvrtc/lib",
        "$ORIGIN/../../nvidia/cudnn/lib",
        "$ORIGIN/../../nvidia/nccl/lib",
        "$ORIGIN/../../mlx_cuda_12.libs",
    ]
)


def host_library_name(base: str) -> str:
    system = platform.system()
    if system == "Darwin":
        return f"lib{base}.dylib"
    if system == "Windows":
        return f"{base}.dll"
    return f"lib{base}.so"


def default_mlx_prefix() -> Path:
    env = os.environ.get("KIWI_MLX_PREFIX")
    if env:
        return Path(env).expanduser()
    if (WORKSPACE_ROOT / "vendor" / "mlx-c").exists():
        if platform.system() == "Linux":
            machine = platform.machine()
            arch = "aarch64" if machine in {"aarch64", "arm64"} else "x86_64"
            return WORKSPACE_ROOT / ".artifacts" / "mlx" / f"linux-{arch}-install"
        return WORKSPACE_ROOT / ".artifacts" / "mlx" / "macos-default-install"
    return KIWI_ROOT / ".deps" / "mlx"


def default_duckdb_prefix() -> Path:
    env = os.environ.get("KIWI_DUCKDB_PREFIX")
    if env:
        return Path(env).expanduser()
    local = KIWI_ROOT / ".deps" / "duckdb"
    if local.exists():
        return local
    return WORKSPACE_ROOT / ".artifacts" / "duckdb" / "macos-universal"


def clean_payload_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    for child in path.iterdir():
        if child.name == ".gitignore":
            continue
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()


def copy_required(src: Path, dst_dir: Path) -> Path:
    if not src.exists():
        raise FileNotFoundError(f"required runtime payload not found: {src}")
    dst = dst_dir / src.name
    shutil.copy2(src, dst)
    return dst


def copy_optional(src: Path, dst_dir: Path) -> Path | None:
    if not src.exists():
        return None
    dst = dst_dir / src.name
    shutil.copy2(src, dst)
    return dst


def is_runtime_library(path: Path) -> bool:
    name = path.name
    if not path.is_file() or name.startswith("libkiwi_bridge"):
        return False
    if platform.system() == "Linux" and name in LINUX_TOOLCHAIN_RUNTIME_NAMES:
        return False
    if name.endswith(".a"):
        return False
    return name.startswith("lib") and (
        ".so" in name or name.endswith(".dylib") or name.endswith(".dll")
    )


def copy_prefix_runtime_libraries(prefix: Path, dst_dir: Path) -> None:
    lib_dir = prefix / "lib"
    if not lib_dir.is_dir():
        return
    for child in sorted(lib_dir.iterdir()):
        if is_runtime_library(child):
            copy_optional(child, dst_dir)


def macos_rpaths(binary: Path) -> list[str]:
    if platform.system() != "Darwin" or not shutil.which("otool"):
        return []
    result = subprocess.run(
        ["otool", "-l", str(binary)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    rpaths: list[str] = []
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if line.startswith("path "):
            path = line.removeprefix("path ").rsplit(" (offset ", 1)[0]
            rpaths.append(path)
    return rpaths


def normalize_macos_rpaths(binary: Path) -> None:
    if platform.system() != "Darwin" or not shutil.which("install_name_tool"):
        return
    wanted = "@loader_path/../lib"
    for rpath in macos_rpaths(binary):
        if rpath != wanted and not rpath.startswith("@loader_path"):
            subprocess.run(["install_name_tool", "-delete_rpath", rpath, str(binary)], check=True)
    if wanted not in macos_rpaths(binary):
        subprocess.run(["install_name_tool", "-add_rpath", wanted, str(binary)], check=True)


def normalize_linux_rpath(binary: Path, rpath: str) -> None:
    if platform.system() != "Linux" or not shutil.which("patchelf"):
        return
    subprocess.run(["patchelf", "--force-rpath", "--set-rpath", rpath, str(binary)], check=True)


def normalize_linux_library_rpaths(lib_dir: Path) -> None:
    if platform.system() != "Linux":
        return
    for child in sorted(lib_dir.iterdir()):
        if is_runtime_library(child):
            rpath = LINUX_MLX_CUDA_RPATH if child.name.startswith("libmlx.") else "$ORIGIN"
            normalize_linux_rpath(child, rpath)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Stage native libraries into the kiwilang wheel package.")
    parser.add_argument("--prefix", type=Path, default=KIWI_ROOT / "zig-out", help="Kiwi install prefix containing libkiwi_bridge.")
    parser.add_argument("--runtime-backend", choices=("host", "mlx"), default="mlx", help="Runtime backend staged into the wheel.")
    parser.add_argument("--runtime-package", type=Path, default=RUNTIME_PACKAGE, help="kiwilang package directory to receive native payloads.")
    parser.add_argument("--mlx-prefix", type=Path, default=default_mlx_prefix(), help="MLX install prefix.")
    parser.add_argument("--duckdb-prefix", type=Path, default=default_duckdb_prefix(), help="DuckDB install prefix.")
    parser.add_argument("--bridge-lib", type=Path, help="Explicit libkiwi_bridge path.")
    parser.add_argument("--allow-missing-duckdb", action="store_true", help="Stage a wheel without libduckdb.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    native_dir = args.runtime_package / "native"
    lib_dir = args.runtime_package / "lib"
    clean_payload_dir(native_dir)
    clean_payload_dir(lib_dir)

    bridge = args.bridge_lib or args.prefix / "lib" / host_library_name("kiwi_bridge")
    staged_bridge = copy_required(bridge, native_dir)
    normalize_macos_rpaths(staged_bridge)
    normalize_linux_rpath(staged_bridge, "$ORIGIN/../lib")

    copy_prefix_runtime_libraries(args.prefix, lib_dir)
    copy_prefix_runtime_libraries(args.duckdb_prefix, lib_dir)
    if args.runtime_backend == "mlx":
        copy_prefix_runtime_libraries(args.mlx_prefix, lib_dir)
        copy_required(args.mlx_prefix / "lib" / host_library_name("mlx"), lib_dir)
        copy_optional(args.mlx_prefix / "lib" / "mlx.metallib", lib_dir)

    duckdb_candidates = [
        args.prefix / "lib" / host_library_name("duckdb"),
        args.duckdb_prefix / "lib" / host_library_name("duckdb"),
        args.duckdb_prefix / host_library_name("duckdb"),
        KIWI_ROOT / "zig-out" / "lib" / host_library_name("duckdb"),
    ]
    for candidate in duckdb_candidates:
        staged = copy_optional(candidate, lib_dir)
        if staged is not None:
            break
    else:
        if not args.allow_missing_duckdb:
            joined = ", ".join(str(candidate) for candidate in duckdb_candidates)
            raise FileNotFoundError(f"required libduckdb not found. Searched: {joined}")

    normalize_linux_library_rpaths(lib_dir)

    print(f"staged native bridge: {staged_bridge}")
    print(f"staged runtime libs: {lib_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
