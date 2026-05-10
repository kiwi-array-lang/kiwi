from __future__ import annotations

import argparse
from importlib import resources
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any, Optional

from .binding import (
    DEVICE_ENV_VAR,
    LIB_ENV_VAR,
    build_bridge,
    experiment_root,
    find_library_path,
    runtime_library_env_var,
    runtime_library_search_dir,
)

DEFAULT_KERNEL_NAME = "kiwi"
DEFAULT_DISPLAY_NAME = "Kiwi"


def default_logo_candidates() -> list[Path]:
    return [
        Path(__file__).resolve().parent / "assets" / "kernel-logo.png",
    ]


def find_logo_path(path: Optional[str | Path] = None) -> Optional[Path]:
    if path is not None:
        candidate = Path(path).expanduser()
        if candidate.exists():
            return candidate
        raise FileNotFoundError(f"Kiwi kernel logo not found at {candidate}")

    for candidate in default_logo_candidates():
        if candidate.exists():
            return candidate
    return None


def write_kernel_logos(dst_dir: Path, logo_path: Optional[str | Path] = None) -> None:
    source = find_logo_path(logo_path)
    if source is not None:
        for name in ("logo-32x32.png", "logo-64x64.png"):
            shutil.copy2(source, dst_dir / name)
        return

    resource = resources.files("kiwi_jupyter_kernel") / "assets" / "kernel-logo.png"
    with resources.as_file(resource) as resource_path:
        for name in ("logo-32x32.png", "logo-64x64.png"):
            shutil.copy2(resource_path, dst_dir / name)


def build_kernel_spec(
    display_name: str = DEFAULT_DISPLAY_NAME,
    device: str = "auto",
    python_executable: Optional[str] = None,
    library_path: Optional[str] = None,
) -> dict[str, Any]:
    python_cmd = python_executable or sys.executable
    env = {
        DEVICE_ENV_VAR: device,
    }
    runtime_env_var = runtime_library_env_var()
    if runtime_env_var is not None:
        runtime_dir = runtime_library_search_dir()
        existing = os.environ.get(runtime_env_var)
        env[runtime_env_var] = (
            os.pathsep.join([str(runtime_dir), existing]) if existing else str(runtime_dir)
        )
    if library_path is not None:
        env[LIB_ENV_VAR] = library_path
    return {
        "argv": [python_cmd, "-m", "kiwi_jupyter_kernel", "-f", "{connection_file}"],
        "display_name": display_name,
        "language": "kiwi",
        "env": env,
    }


def install_kernel(
    name: str = DEFAULT_KERNEL_NAME,
    display_name: str = DEFAULT_DISPLAY_NAME,
    device: str = "auto",
    user: bool = True,
    prefix: Optional[str] = None,
    skip_build: bool = False,
    optimize: str = "ReleaseFast",
) -> str:
    if not skip_build:
        build_bridge(optimize=optimize)

    from jupyter_client.kernelspec import KernelSpecManager

    try:
        library_path = str(find_library_path())
    except FileNotFoundError:
        library_path = None

    spec = build_kernel_spec(display_name=display_name, device=device, library_path=library_path)
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        (tmp_path / "kernel.json").write_text(json.dumps(spec, indent=2) + "\n")
        write_kernel_logos(tmp_path)
        return KernelSpecManager().install_kernel_spec(tmpdir, kernel_name=name, user=user, prefix=prefix)


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Install the Kiwi Jupyter kernel.")
    parser.add_argument("--name", default=DEFAULT_KERNEL_NAME, help="Kernel name used by Jupyter.")
    parser.add_argument("--display-name", default=DEFAULT_DISPLAY_NAME, help="Kernel display name shown in Jupyter.")
    parser.add_argument("--device", choices=("auto", "cpu", "gpu"), default="auto", help="Default Kiwi device for the kernel.")
    parser.add_argument("--optimize", choices=("Debug", "ReleaseFast", "ReleaseSafe", "ReleaseSmall"), default="ReleaseFast", help="Zig optimize mode used when building the bridge.")
    parser.add_argument("--skip-build", action="store_true", help="Skip `zig build` before installing the kernelspec.")
    parser.add_argument("--prefix", help="Install the kernelspec under the given prefix.")
    parser.add_argument("--sys-prefix", action="store_true", help="Install the kernelspec into the current Python environment prefix.")
    parser.add_argument("--user", action="store_true", help="Install the kernelspec into the user Jupyter data dir (default).")
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv)
    prefix = args.prefix
    user = True
    if args.sys_prefix:
        prefix = sys.prefix
        user = False
    elif args.prefix is not None:
        user = False

    location = install_kernel(
        name=args.name,
        display_name=args.display_name,
        device=args.device,
        user=user,
        prefix=prefix,
        skip_build=args.skip_build,
        optimize=args.optimize,
    )
    print(location)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
