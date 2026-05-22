from __future__ import annotations

from pathlib import Path
import sys

RUNTIME_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_SRC = RUNTIME_ROOT / "src"
if str(RUNTIME_SRC) not in sys.path:
    sys.path.insert(0, str(RUNTIME_SRC))

from kiwi_array import bridge as kiwi_bridge


def test_runtime_library_search_dir_ignores_wrong_platform_payload(tmp_path, monkeypatch) -> None:
    package_lib = tmp_path / "package-lib"
    package_native = tmp_path / "package-native"
    package_lib.mkdir()
    package_native.mkdir()
    (package_native / kiwi_bridge.platform_library_name("kiwi_bridge")).write_text("")
    wrong_payload = "libmlx.so" if kiwi_bridge.platform_library_name("mlx").endswith(".dylib") else "libmlx.dylib"
    (package_lib / wrong_payload).write_text("")

    mlx_prefix = tmp_path / "mlx"
    (mlx_prefix / "lib").mkdir(parents=True)

    descriptor = kiwi_bridge.RuntimeDescriptor(
        name="test",
        priority=80,
        backend="mlx",
        accelerator=None,
        native_dir=package_native,
        lib_dir=package_lib,
        source="test",
    )
    monkeypatch.setattr(kiwi_bridge, "discover_runtime_descriptors", lambda: [descriptor])
    monkeypatch.setattr(kiwi_bridge, "_find_source_root", lambda: None)
    monkeypatch.setattr(kiwi_bridge, "mlx_prefix", lambda: mlx_prefix)

    assert kiwi_bridge.runtime_library_search_dir() == mlx_prefix / "lib"


def test_runtime_library_search_dir_prefers_matching_packaged_payload(tmp_path, monkeypatch) -> None:
    package_lib = tmp_path / "package-lib"
    package_native = tmp_path / "package-native"
    package_lib.mkdir()
    package_native.mkdir()
    (package_native / kiwi_bridge.platform_library_name("kiwi_bridge")).write_text("")
    (package_lib / kiwi_bridge.platform_library_name("mlx")).write_text("")

    mlx_prefix = tmp_path / "mlx"
    (mlx_prefix / "lib").mkdir(parents=True)

    descriptor = kiwi_bridge.RuntimeDescriptor(
        name="test",
        priority=80,
        backend="mlx",
        accelerator=None,
        native_dir=package_native,
        lib_dir=package_lib,
        source="test",
    )
    monkeypatch.setattr(kiwi_bridge, "discover_runtime_descriptors", lambda: [descriptor])
    monkeypatch.setattr(kiwi_bridge, "_find_source_root", lambda: None)
    monkeypatch.setattr(kiwi_bridge, "mlx_prefix", lambda: mlx_prefix)

    assert kiwi_bridge.runtime_library_search_dir() == package_lib


def test_discover_runtime_descriptors_includes_embedded_host() -> None:
    descriptors = {descriptor.name: descriptor for descriptor in kiwi_bridge.discover_runtime_descriptors()}

    assert descriptors["host"].backend == "host"


def test_default_library_candidates_respects_runtime_selection(tmp_path, monkeypatch) -> None:
    runtime_root = tmp_path / "runtime"
    native_dir = runtime_root / "native"
    lib_dir = runtime_root / "lib"
    native_dir.mkdir(parents=True)
    lib_dir.mkdir()
    (native_dir / kiwi_bridge.platform_library_name("kiwi_bridge")).write_text("")

    descriptor = kiwi_bridge.RuntimeDescriptor(
        name="cuda12",
        priority=80,
        backend="mlx",
        accelerator="cuda",
        native_dir=native_dir,
        lib_dir=lib_dir,
        source="test",
    )
    monkeypatch.setattr(kiwi_bridge, "discover_runtime_descriptors", lambda: [descriptor])
    monkeypatch.setenv(kiwi_bridge.RUNTIME_ENV_VAR, "cuda12")

    assert kiwi_bridge.default_library_candidates()[0] == descriptor.bridge_library_path()


def test_cuda_driver_preload_is_opt_in(monkeypatch) -> None:
    calls = []
    monkeypatch.setattr(kiwi_bridge.platform, "system", lambda: "Linux")
    monkeypatch.setattr(kiwi_bridge.ctypes, "CDLL", lambda *args, **kwargs: calls.append((args, kwargs)))
    monkeypatch.delenv(kiwi_bridge.CUDA_PRELOAD_DRIVER_ENV_VAR, raising=False)

    kiwi_bridge._preload_cuda_driver()

    assert calls == []


def test_cuda_driver_preload_honors_explicit_override(tmp_path, monkeypatch) -> None:
    driver = tmp_path / "libcuda.so.1"
    driver.write_text("")
    calls = []
    monkeypatch.setattr(kiwi_bridge.platform, "system", lambda: "Linux")
    monkeypatch.setattr(kiwi_bridge.ctypes, "CDLL", lambda *args, **kwargs: calls.append((args, kwargs)))
    monkeypatch.setenv(kiwi_bridge.CUDA_PRELOAD_DRIVER_ENV_VAR, "1")
    monkeypatch.setenv(kiwi_bridge.CUDA_DRIVER_LIB_ENV_VAR, str(driver))
    monkeypatch.setattr(kiwi_bridge.ctypes.util, "find_library", lambda name: None)

    kiwi_bridge._preload_cuda_driver()

    assert calls[0][0][0] == str(driver)


def test_find_cli_path_uses_selected_runtime_descriptor(tmp_path, monkeypatch) -> None:
    runtime_root = tmp_path / "runtime"
    bin_dir = runtime_root / "bin"
    native_dir = runtime_root / "native"
    lib_dir = runtime_root / "lib"
    bin_dir.mkdir(parents=True)
    native_dir.mkdir()
    lib_dir.mkdir()
    cli = bin_dir / kiwi_bridge.platform_executable_name("kiwi")
    cli.write_text("")

    descriptor = kiwi_bridge.RuntimeDescriptor(
        name="host",
        priority=20,
        backend="host",
        accelerator=None,
        native_dir=native_dir,
        lib_dir=lib_dir,
        bin_dir=bin_dir,
        source="test",
    )
    monkeypatch.setattr(kiwi_bridge, "discover_runtime_descriptors", lambda: [descriptor])
    monkeypatch.setattr(kiwi_bridge, "_find_source_root", lambda: None)
    monkeypatch.setenv(kiwi_bridge.RUNTIME_ENV_VAR, "host")

    assert kiwi_bridge.find_cli_path() == cli
