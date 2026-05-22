from __future__ import annotations

from pathlib import Path

__version__ = "0.2.50"


def _package_root() -> Path:
    return Path(__file__).resolve().parent


def runtime_descriptor() -> dict[str, object]:
    root = _package_root()
    return {
        "name": "metal",
        "priority": 70,
        "backend": "mlx",
        "accelerator": "metal",
        "bin_dir": str(root / "bin"),
        "native_dir": str(root / "native"),
        "lib_dir": str(root / "lib"),
    }


__all__ = ["__version__", "runtime_descriptor"]
