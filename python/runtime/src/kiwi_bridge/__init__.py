from __future__ import annotations

import ctypes
import ctypes.util
import os
import platform
import shutil
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence, Union

try:
    import numpy as _np
except ImportError:  # pragma: no cover - optional dependency
    _np = None

LIB_ENV_VAR = "KIWI_BRIDGE_LIB"
LEGACY_LIB_ENV_VAR = "KIWI_JUPYTER_BRIDGE_LIB"
SOURCE_ROOT_ENV_VAR = "KIWI_SOURCE_ROOT"
ZIG_ENV_VAR = "KIWI_ZIG"
MLX_PREFIX_ENV_VAR = "KIWI_MLX_PREFIX"
MLX_C_INCLUDE_ENV_VAR = "KIWI_MLX_C_INCLUDE"

DEVICE_VALUES = {
    "auto": 0,
    "cpu": 1,
    "gpu": 2,
}

STATUS_NAMES = {
    0: "ok",
    1: "parse",
    2: "type",
    3: "name",
    4: "domain",
    5: "rank",
    6: "nyi",
    7: "length",
    8: "index",
    9: "mlx",
    10: "device",
    11: "error",
    12: "oom",
}

AUTOGRAD_PATH_NAMES = {
    0: "none",
    1: "mlx",
    2: "finite_difference",
}

PathLikeArg = Union[os.PathLike[str], str]


class _CKiwiEvalResult(ctypes.Structure):
    _fields_ = [
        ("status", ctypes.c_int),
        ("echoed", ctypes.c_bool),
        ("autograd_path", ctypes.c_int),
        ("text_ptr", ctypes.c_void_p),
        ("text_len", ctypes.c_size_t),
        ("display_mime_ptr", ctypes.c_void_p),
        ("display_mime_len", ctypes.c_size_t),
        ("display_data_ptr", ctypes.c_void_p),
        ("display_data_len", ctypes.c_size_t),
    ]


@dataclass(frozen=True)
class KiwiEvalResult:
    status: str
    echoed: bool
    autograd_path: str
    text: Optional[str]
    display_mime: Optional[str] = None
    display_data: Optional[str] = None


class KiwiBridgeError(RuntimeError):
    pass


def _find_source_root() -> Optional[Path]:
    override = os.environ.get(SOURCE_ROOT_ENV_VAR)
    if override:
        return Path(override).expanduser()

    for parent in Path(__file__).resolve().parents:
        if (parent / "build.zig").is_file() and (parent / "src" / "kiwi_bridge.zig").is_file():
            return parent
    return None


def implementation_root() -> Path:
    root = _find_source_root()
    if root is None:
        raise KiwiBridgeError(
            "Kiwi source root not found. Set KIWI_SOURCE_ROOT when building the "
            "bridge from source, or install a platform wheel that carries the "
            "native Kiwi runtime."
        )
    return root


def _has_workspace_dependency_layout() -> bool:
    root = _find_source_root()
    if root is None:
        return False
    return (root.parents[1] / "vendor" / "mlx-c").exists()


def repo_root() -> Path:
    root = implementation_root()
    return root.parents[1] if _has_workspace_dependency_layout() else root


def _package_root() -> Optional[Path]:
    try:
        import kiwilang
    except ImportError:
        return None
    module_file = getattr(kiwilang, "__file__", None)
    if module_file is None:
        return None
    return Path(module_file).resolve().parent


def _packaged_native_dir() -> Optional[Path]:
    root = _package_root()
    return None if root is None else root / "native"


def _packaged_library_dir() -> Optional[Path]:
    root = _package_root()
    return None if root is None else root / "lib"


def _is_platform_dynamic_library_name(name: str) -> bool:
    system = platform.system()
    if system == "Darwin":
        return name.endswith(".dylib")
    if system == "Windows":
        return name.endswith(".dll")
    return ".so" in name


def _dir_has_payload(path: Optional[Path]) -> bool:
    if path is None or not path.is_dir():
        return False
    return any(
        child.is_file()
        and child.name not in {".gitignore", ".gitkeep"}
        and _is_platform_dynamic_library_name(child.name)
        for child in path.iterdir()
    )


def zig_executable() -> str:
    override = os.environ.get(ZIG_ENV_VAR) or os.environ.get("ZIG")
    if override:
        return str(Path(override).expanduser())
    bundled = repo_root() / "tools" / "zig"
    if bundled.exists():
        return str(bundled)
    path_zig = shutil.which("zig")
    return path_zig if path_zig is not None else "zig"


def default_mlx_prefix() -> Path:
    if _has_workspace_dependency_layout():
        return repo_root() / ".artifacts" / "mlx" / "macos-default-install"
    return implementation_root() / ".deps" / "mlx"


def default_mlx_c_include() -> Path:
    if _has_workspace_dependency_layout():
        return repo_root() / "vendor" / "mlx-c"
    return implementation_root() / ".deps" / "mlx-c"


def mlx_prefix() -> Path:
    return Path(
        os.environ.get(MLX_PREFIX_ENV_VAR)
        or default_mlx_prefix()
    ).expanduser()


def mlx_c_include() -> Path:
    return Path(
        os.environ.get(MLX_C_INCLUDE_ENV_VAR)
        or default_mlx_c_include()
    ).expanduser()


def runtime_library_search_dir() -> Path:
    packaged_lib = _packaged_library_dir()
    if _dir_has_payload(packaged_lib):
        return packaged_lib
    return mlx_prefix() / "lib"


def runtime_library_env_var() -> Optional[str]:
    system = platform.system()
    if system == "Darwin":
        return "DYLD_LIBRARY_PATH"
    if system == "Linux":
        return "LD_LIBRARY_PATH"
    return None


def build_args(optimize: str) -> list[str]:
    bridge_mlx_prefix = mlx_prefix()
    bridge_mlx_c_include = mlx_c_include()
    return [
        zig_executable(),
        "build",
        f"-Doptimize={optimize}",
        "-Dpublic-cli=true",
        "-Dinstall-sdk=true",
        f"-Dmlx-prefix={bridge_mlx_prefix}",
        f"-Dmlx-c-include={bridge_mlx_c_include}",
    ]


def platform_library_name(base_name: str) -> str:
    system = platform.system()
    if system == "Darwin":
        return f"lib{base_name}.dylib"
    if system == "Windows":
        return f"{base_name}.dll"
    return f"lib{base_name}.so"


def default_library_candidates() -> list[Path]:
    candidates: list[Path] = []
    for env_var in (LIB_ENV_VAR, LEGACY_LIB_ENV_VAR):
        env_path = os.environ.get(env_var)
        if env_path:
            candidates.append(Path(env_path).expanduser())

    packaged_native = _packaged_native_dir()
    if packaged_native is not None:
        candidates.append(packaged_native / platform_library_name("kiwi_bridge"))

    source_root = _find_source_root()
    if source_root is not None:
        candidates.append(source_root / "zig-out" / "lib" / platform_library_name("kiwi_bridge"))
    return candidates


def find_library_path(path: Optional[PathLikeArg] = None) -> Path:
    if path is not None:
        candidate = Path(path).expanduser()
        if candidate.exists():
            return candidate
        raise FileNotFoundError(f"Kiwi bridge library not found at {candidate}")

    for candidate in default_library_candidates():
        if candidate.exists():
            return candidate
    joined = ", ".join(str(candidate) for candidate in default_library_candidates())
    source_root = _find_source_root()
    if source_root is None:
        hint = "Install a platform wheel that carries the native Kiwi runtime."
    else:
        hint = f"Build it with `{shlex.join(build_args('ReleaseFast'))}` from {source_root}."
    raise FileNotFoundError(f"Kiwi bridge library not found. {hint} Searched: {joined}")


def build_bridge(optimize: str = "ReleaseFast") -> None:
    subprocess.run(
        build_args(optimize),
        cwd=implementation_root(),
        check=True,
    )


def _configure_library(lib: ctypes.CDLL) -> ctypes.CDLL:
    lib.kiwi_session_create.argtypes = [ctypes.c_int]
    lib.kiwi_session_create.restype = ctypes.c_void_p

    lib.kiwi_session_destroy.argtypes = [ctypes.c_void_p]
    lib.kiwi_session_destroy.restype = None

    lib.kiwi_session_eval.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
    lib.kiwi_session_eval.restype = _CKiwiEvalResult

    lib.kiwi_session_set_global_float_array.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_float),
        ctypes.POINTER(ctypes.c_int32),
        ctypes.c_size_t,
    ]
    lib.kiwi_session_set_global_float_array.restype = ctypes.c_int

    if hasattr(lib, "kiwi_session_set_global_mlx_float_array"):
        lib.kiwi_session_set_global_mlx_float_array.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_size_t,
            ctypes.POINTER(ctypes.c_float),
            ctypes.POINTER(ctypes.c_int32),
            ctypes.c_size_t,
        ]
        lib.kiwi_session_set_global_mlx_float_array.restype = ctypes.c_int

    lib.kiwi_session_set_global_int_array.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_int32),
        ctypes.POINTER(ctypes.c_int32),
        ctypes.c_size_t,
    ]
    lib.kiwi_session_set_global_int_array.restype = ctypes.c_int

    lib.kiwi_session_set_global_bool_array.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_bool),
        ctypes.POINTER(ctypes.c_int32),
        ctypes.c_size_t,
    ]
    lib.kiwi_session_set_global_bool_array.restype = ctypes.c_int

    lib.kiwi_eval_result_free.argtypes = [_CKiwiEvalResult]
    lib.kiwi_eval_result_free.restype = None

    lib.kiwi_status_name.argtypes = [ctypes.c_int]
    lib.kiwi_status_name.restype = ctypes.c_char_p
    return lib


def _preload_runtime_dependencies() -> None:
    _preload_cuda_driver()

    search_dirs = [runtime_library_search_dir()]
    packaged_lib = _packaged_library_dir()
    if packaged_lib is not None:
        search_dirs.append(packaged_lib)
    source_root = _find_source_root()
    if source_root is not None:
        search_dirs.append(source_root / "zig-out" / "lib")

    seen: set[Path] = set()
    for directory in search_dirs:
        if directory in seen:
            continue
        seen.add(directory)
        for base_name in ("mlx", "duckdb"):
            library = directory / platform_library_name(base_name)
            if library.exists():
                ctypes.CDLL(str(library), mode=getattr(ctypes, "RTLD_GLOBAL", 0))


def _preload_cuda_driver() -> None:
    if platform.system() != "Linux":
        return

    candidates = []
    override = os.environ.get("KIWI_CUDA_DRIVER_LIB")
    if override:
        candidates.append(Path(override).expanduser())
    candidates.extend(
        [
            Path("/usr/lib64-nvidia/libcuda.so.1"),
            Path("/usr/local/cuda/compat/libcuda.so.1"),
            Path("/usr/lib/x86_64-linux-gnu/libcuda.so.1"),
        ]
    )
    found = ctypes.util.find_library("cuda")
    if found:
        candidates.append(Path(found))

    for candidate in candidates:
        try:
            if candidate.is_absolute() and not candidate.exists():
                continue
            ctypes.CDLL(str(candidate), mode=getattr(ctypes, "RTLD_GLOBAL", 0))
            return
        except OSError:
            continue


def load_library(path: Optional[PathLikeArg] = None) -> ctypes.CDLL:
    _preload_runtime_dependencies()
    return _configure_library(ctypes.CDLL(str(find_library_path(path))))


def _normalize_dims(dims: Optional[Sequence[int]], data) -> tuple[int, ...]:
    if dims is not None:
        return tuple(int(dim) for dim in dims)

    shape = getattr(data, "shape", None)
    if shape is None:
        raise TypeError("dims are required unless data exposes a shape")
    return tuple(int(dim) for dim in shape)


def _product(dims: Sequence[int]) -> int:
    total = 1
    for dim in dims:
        if dim < 0:
            raise ValueError(f"negative dimension {dim}")
        total *= dim
    return total


def _sequence_values(data, count: int):
    if count == 1 and not isinstance(data, (list, tuple)):
        return [data]
    values = list(data)
    if len(values) != count:
        raise ValueError(f"expected {count} items, got {len(values)}")
    return values


def _prepare_array_data(data, dims: tuple[int, ...], c_type, numpy_dtype):
    count = _product(dims)
    if _np is not None:
        arr = _np.asarray(data, dtype=numpy_dtype)
        if arr.size != count:
            raise ValueError(f"expected {count} items, got {arr.size}")
        flat = _np.ascontiguousarray(arr.reshape(-1))
        ptr = None if count == 0 else flat.ctypes.data_as(ctypes.POINTER(c_type))
        return flat, ptr

    values = _sequence_values(data, count)
    buf = (c_type * count)(*values)
    ptr = None if count == 0 else buf
    return buf, ptr


class KiwiSession:
    def __init__(self, device: str = "auto", library_path: Optional[PathLikeArg] = None) -> None:
        try:
            device_value = DEVICE_VALUES[device]
        except KeyError as exc:
            raise ValueError(f"unknown Kiwi device {device!r}") from exc

        self._lib = load_library(library_path)
        self._handle = self._lib.kiwi_session_create(device_value)
        if not self._handle:
            raise KiwiBridgeError("failed to create Kiwi session")

    def close(self) -> None:
        if self._handle:
            self._lib.kiwi_session_destroy(self._handle)
            self._handle = None

    def eval(self, source: str) -> KiwiEvalResult:
        self._ensure_open()
        encoded = source.encode("utf-8")
        result = self._lib.kiwi_session_eval(self._handle, encoded, len(encoded))
        try:
            text = None
            if result.text_ptr:
                text = ctypes.string_at(result.text_ptr, result.text_len).decode("utf-8")
            display_mime = None
            if result.display_mime_ptr:
                display_mime = ctypes.string_at(
                    result.display_mime_ptr,
                    result.display_mime_len,
                ).decode("utf-8")
            display_data = None
            if result.display_data_ptr:
                display_data = ctypes.string_at(
                    result.display_data_ptr,
                    result.display_data_len,
                ).decode("utf-8")
            return KiwiEvalResult(
                status=STATUS_NAMES.get(result.status, "error"),
                echoed=bool(result.echoed),
                autograd_path=AUTOGRAD_PATH_NAMES.get(result.autograd_path, "none"),
                text=text,
                display_mime=display_mime,
                display_data=display_data,
            )
        finally:
            self._lib.kiwi_eval_result_free(result)

    def set_global_float_array(self, name: str, data, dims: Optional[Sequence[int]] = None) -> None:
        self._set_global_array(
            "kiwi_session_set_global_float_array",
            name,
            data,
            dims,
            ctypes.c_float,
            _np.float32 if _np is not None else None,
        )

    def set_global_mlx_float_array(self, name: str, data, dims: Optional[Sequence[int]] = None) -> None:
        self._set_global_array(
            "kiwi_session_set_global_mlx_float_array",
            name,
            data,
            dims,
            ctypes.c_float,
            _np.float32 if _np is not None else None,
        )

    def set_global_int_array(self, name: str, data, dims: Optional[Sequence[int]] = None) -> None:
        self._set_global_array(
            "kiwi_session_set_global_int_array",
            name,
            data,
            dims,
            ctypes.c_int32,
            _np.int32 if _np is not None else None,
        )

    def set_global_bool_array(self, name: str, data, dims: Optional[Sequence[int]] = None) -> None:
        self._set_global_array(
            "kiwi_session_set_global_bool_array",
            name,
            data,
            dims,
            ctypes.c_bool,
            _np.bool_ if _np is not None else None,
        )

    def __enter__(self) -> "KiwiSession":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def _ensure_open(self) -> None:
        if not self._handle:
            raise KiwiBridgeError("Kiwi session is closed")

    def _set_global_array(
        self,
        fn_name: str,
        name: str,
        data,
        dims: Optional[Sequence[int]],
        c_type,
        numpy_dtype,
    ) -> None:
        self._ensure_open()
        if not hasattr(self._lib, fn_name):
            raise KiwiBridgeError(f"native Kiwi bridge does not expose {fn_name}")
        dims_tuple = _normalize_dims(dims, data)
        owner, data_ptr = _prepare_array_data(data, dims_tuple, c_type, numpy_dtype)
        dims_owner = (ctypes.c_int32 * len(dims_tuple))(*dims_tuple)
        dims_ptr = None if len(dims_tuple) == 0 else dims_owner
        encoded = name.encode("utf-8")
        status = getattr(self._lib, fn_name)(
            self._handle,
            encoded,
            len(encoded),
            data_ptr,
            dims_ptr,
            len(dims_tuple),
        )
        _ = owner
        if status != 0:
            raise KiwiBridgeError(f"failed to set global {name!r}: {STATUS_NAMES.get(status, 'error')}")


__all__ = [
    "AUTOGRAD_PATH_NAMES",
    "KiwiBridgeError",
    "KiwiEvalResult",
    "KiwiSession",
    "LEGACY_LIB_ENV_VAR",
    "LIB_ENV_VAR",
    "STATUS_NAMES",
    "build_bridge",
    "default_library_candidates",
    "find_library_path",
    "implementation_root",
    "load_library",
    "platform_library_name",
    "runtime_library_env_var",
    "runtime_library_search_dir",
]
