from __future__ import annotations

import sys
from pathlib import Path

DEVICE_ENV_VAR = "KIWI_JUPYTER_DEVICE"


def jupyter_root() -> Path:
    return Path(__file__).resolve().parents[2]


def python_root() -> Path:
    return jupyter_root().parent


def kiwi_root() -> Path:
    return python_root().parent


def experiment_root() -> Path:
    return jupyter_root()


try:
    import kiwi_bridge  # noqa: F401
except ImportError:
    _KIWI_BRIDGE_PYTHON_SRC = python_root() / "runtime" / "src"
    if str(_KIWI_BRIDGE_PYTHON_SRC) not in sys.path:
        sys.path.insert(0, str(_KIWI_BRIDGE_PYTHON_SRC))

from kiwi_bridge import (  # noqa: E402
    AUTOGRAD_PATH_NAMES,
    LEGACY_LIB_ENV_VAR,
    LIB_ENV_VAR,
    STATUS_NAMES,
    KiwiBridgeError,
    KiwiEvalResult,
    KiwiSession,
    build_bridge,
    default_library_candidates,
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
    "STATUS_NAMES",
    "KiwiBridgeError",
    "KiwiEvalResult",
    "KiwiSession",
    "build_bridge",
    "default_library_candidates",
    "experiment_root",
    "find_library_path",
    "implementation_root",
    "jupyter_root",
    "kiwi_root",
    "load_library",
    "platform_library_name",
    "python_root",
    "runtime_library_env_var",
    "runtime_library_search_dir",
]
