#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import tomllib
from pathlib import Path
from typing import Any


KIWI_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = KIWI_ROOT / "deps" / "mlx_runtime_surface.toml"


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open("rb") as fh:
        return tomllib.load(fh)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def patch_text(manifest: dict[str, Any]) -> str:
    chunks: list[str] = []
    for rel in manifest.get("metadata", {}).get("cuda_profile_patches", []):
        chunks.append(read_text(KIWI_ROOT / rel))
    return "\n".join(chunks)


def source_text() -> str:
    paths = [
        KIWI_ROOT / "csrc" / "mlxc_mini.cpp",
        KIWI_ROOT / "src" / "native" / "c.zig",
        KIWI_ROOT / "src" / "native" / "mlx.zig",
        KIWI_ROOT / "src" / "runtime.zig",
    ]
    return "\n".join(read_text(path) for path in paths)


def source_removed_in_profile(source: str, patches: str) -> bool:
    needle = f"${{CMAKE_CURRENT_SOURCE_DIR}}/{source}"
    return any(line.startswith("-") and needle in line for line in patches.splitlines())


def source_added_in_profile_else(source: str, patches: str) -> bool:
    needle = f"${{CMAKE_CURRENT_SOURCE_DIR}}/{source}"
    return any(line.startswith("+") and needle in line for line in patches.splitlines())


def primitive_stubbed(primitive: str, patches: str) -> bool:
    return f"void {primitive}::eval_gpu" in patches


def check_manifest(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    sources = source_text()
    patches = patch_text(manifest)

    for feature in manifest.get("required", []):
        name = feature["name"]
        for symbol in feature.get("bridge_symbols", []):
            if symbol not in sources:
                errors.append(f"required feature {name!r} bridge symbol {symbol!r} is not present")
        for call in feature.get("mlx_calls", []):
            if call not in sources:
                errors.append(f"required feature {name!r} MLX call {call!r} is not present")
        for cuda_source in feature.get("cuda_sources", []):
            if cuda_source.endswith("/"):
                continue
            if source_removed_in_profile(cuda_source, patches):
                errors.append(
                    f"required feature {name!r} CUDA source {cuda_source!r} is removed by kiwi_runtime patches"
                )

    for feature in manifest.get("disabled", []):
        name = feature["name"]
        for call in feature.get("forbidden_mlx_calls", []):
            if call in sources:
                errors.append(f"disabled feature {name!r} appears in Kiwi sources via {call!r}")
        for cuda_source in feature.get("cuda_sources", []):
            if cuda_source.endswith("/"):
                continue
            if not source_removed_in_profile(cuda_source, patches):
                errors.append(
                    f"disabled feature {name!r} CUDA source {cuda_source!r} is not removed by kiwi_runtime patches"
                )
            if not source_added_in_profile_else(cuda_source, patches):
                errors.append(
                    f"disabled feature {name!r} CUDA source {cuda_source!r} is not restored for default MLX builds"
                )
        for primitive in feature.get("stub_primitives", []):
            if primitive in {"Quantize", "ConvertFP8"}:
                if f"void {primitive}::eval_gpu" not in patches:
                    errors.append(f"disabled feature {name!r} primitive {primitive!r} has no eval_gpu stub")
            elif not primitive_stubbed(primitive, patches):
                errors.append(f"disabled feature {name!r} primitive {primitive!r} has no eval_gpu stub")

    return errors


def manifest_summary(manifest: dict[str, Any]) -> dict[str, Any]:
    return {
        "required": [
            {
                "name": feature["name"],
                "bridge_symbols": feature.get("bridge_symbols", []),
                "mlx_calls": feature.get("mlx_calls", []),
                "cuda_sources": feature.get("cuda_sources", []),
            }
            for feature in manifest.get("required", [])
        ],
        "disabled": [
            {
                "name": feature["name"],
                "cuda_sources": feature.get("cuda_sources", []),
                "stub_primitives": feature.get("stub_primitives", []),
            }
            for feature in manifest.get("disabled", [])
        ],
    }


def print_text_summary(manifest: dict[str, Any]) -> None:
    print("Required MLX features:")
    for feature in manifest.get("required", []):
        print(f"- {feature['name']}: {feature.get('reason', '')}")
    print()
    print("Disabled in CUDA kiwi_runtime:")
    for feature in manifest.get("disabled", []):
        print(f"- {feature['name']}: {feature.get('reason', '')}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Inspect and validate Kiwi's MLX runtime surface")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--check", action="store_true", help="validate manifest against bridge sources and CUDA patches")
    parser.add_argument("--json", action="store_true", help="print machine-readable summary")
    args = parser.parse_args(argv)

    manifest = load_manifest(args.manifest)
    if args.check:
        errors = check_manifest(manifest)
        if errors:
            for error in errors:
                print(f"error: {error}", file=sys.stderr)
            return 1

    if args.json:
        print(json.dumps(manifest_summary(manifest), indent=2, sort_keys=True))
    else:
        print_text_summary(manifest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
