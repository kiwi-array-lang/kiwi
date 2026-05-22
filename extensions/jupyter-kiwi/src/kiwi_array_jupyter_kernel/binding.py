from __future__ import annotations

import sys
from pathlib import Path

DEVICE_ENV_VAR = "KIWI_JUPYTER_DEVICE"


def jupyter_root() -> Path:
    return Path(__file__).resolve().parents[2]


def workspace_root() -> Path:
    return jupyter_root().parents[1]


def _kiwi_root_candidates() -> list[Path]:
    root = workspace_root()
    return [
        root,
        root / "implementations" / "kiwi-zig-main",
    ]


def kiwi_root() -> Path:
    for candidate in _kiwi_root_candidates():
        if (candidate / "src" / "kiwi_bridge.zig").is_file():
            return candidate
    return workspace_root()


def python_root() -> Path:
    return kiwi_root() / "python"


def runtime_python_src() -> Path:
    return python_root() / "runtime" / "src"


def experiment_root() -> Path:
    return jupyter_root()


_KIWI_BRIDGE_PYTHON_SRC = runtime_python_src()
if _KIWI_BRIDGE_PYTHON_SRC.exists() and str(_KIWI_BRIDGE_PYTHON_SRC) not in sys.path:
    sys.path.insert(0, str(_KIWI_BRIDGE_PYTHON_SRC))

from kiwi_array.bridge import (  # noqa: E402
    AUTOGRAD_PATH_NAMES,
    LEGACY_LIB_ENV_VAR,
    LIB_ENV_VAR,
    RUNTIME_ENV_VAR,
    STATUS_NAMES,
    KiwiBridgeError,
    KiwiEvalResult,
    KiwiSession,
    active_runtime_descriptor,
    build_bridge,
    default_library_candidates,
    discover_runtime_descriptors,
    find_library_path,
    implementation_root,
    load_library,
    platform_library_name,
    runtime_library_env_var,
    runtime_library_search_dir,
)

__all__ = [
    "AUTOGRAD_PATH_NAMES",
    "DEVICE_ENV_VAR",
    "LEGACY_LIB_ENV_VAR",
    "LIB_ENV_VAR",
    "RUNTIME_ENV_VAR",
    "STATUS_NAMES",
    "KiwiBridgeError",
    "KiwiEvalResult",
    "KiwiSession",
    "active_runtime_descriptor",
    "build_bridge",
    "default_library_candidates",
    "discover_runtime_descriptors",
    "experiment_root",
    "find_library_path",
    "implementation_root",
    "jupyter_root",
    "kiwi_root",
    "load_library",
    "platform_library_name",
    "python_root",
    "runtime_python_src",
    "runtime_library_env_var",
    "runtime_library_search_dir",
    "workspace_root",
]
