from __future__ import annotations

from pathlib import Path

import kiwi_bridge


def test_runtime_library_search_dir_ignores_wrong_platform_payload(tmp_path, monkeypatch) -> None:
    package_lib = tmp_path / "package-lib"
    package_lib.mkdir()
    wrong_payload = "libmlx.so" if kiwi_bridge.platform_library_name("mlx").endswith(".dylib") else "libmlx.dylib"
    (package_lib / wrong_payload).write_text("")

    mlx_prefix = tmp_path / "mlx"
    (mlx_prefix / "lib").mkdir(parents=True)

    monkeypatch.setattr(kiwi_bridge, "_packaged_library_dir", lambda: package_lib)
    monkeypatch.setattr(kiwi_bridge, "mlx_prefix", lambda: mlx_prefix)

    assert kiwi_bridge.runtime_library_search_dir() == mlx_prefix / "lib"


def test_runtime_library_search_dir_prefers_matching_packaged_payload(tmp_path, monkeypatch) -> None:
    package_lib = tmp_path / "package-lib"
    package_lib.mkdir()
    (package_lib / kiwi_bridge.platform_library_name("mlx")).write_text("")

    mlx_prefix = tmp_path / "mlx"
    (mlx_prefix / "lib").mkdir(parents=True)

    monkeypatch.setattr(kiwi_bridge, "_packaged_library_dir", lambda: package_lib)
    monkeypatch.setattr(kiwi_bridge, "mlx_prefix", lambda: mlx_prefix)

    assert kiwi_bridge.runtime_library_search_dir() == package_lib
