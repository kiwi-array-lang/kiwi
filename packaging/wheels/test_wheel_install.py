#!/usr/bin/env python3

from __future__ import annotations

import argparse
import importlib


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Smoke-test installed Kiwi Array wheels.")
    parser.add_argument(
        "--expect-runtime",
        action="append",
        default=[],
        help="Runtime descriptor name expected from kiwi_array.bridge discovery.",
    )
    parser.add_argument("--skip-jupyter", action="store_true", help="Do not import the Jupyter package.")
    parser.add_argument("--skip-eval", action="store_true", help="Do not run a Kiwi eval smoke test.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    kiwi_bridge = importlib.import_module("kiwi_array.bridge")
    jupyter_kernel = None
    if not args.skip_jupyter:
        jupyter_kernel = importlib.import_module("kiwi_array_jupyter_kernel")
    kiwi_array = importlib.import_module("kiwi_array")
    descriptors = kiwi_bridge.discover_runtime_descriptors()
    descriptor_names = {descriptor.name for descriptor in descriptors}
    print(f"kiwi_array {kiwi_array.__version__}")
    if jupyter_kernel is not None:
        print(f"kiwi_array_jupyter_kernel {jupyter_kernel.__version__}")
    print(f"runtime descriptors: {sorted(descriptor_names)}")
    for expected in args.expect_runtime:
        if expected not in descriptor_names:
            raise RuntimeError(
                f"missing runtime descriptor {expected!r}; found {sorted(descriptor_names)}"
            )
    print(f"bridge candidates: {kiwi_bridge.default_library_candidates()}")
    print(f"bridge library: {kiwi_bridge.find_library_path()}")
    if not args.skip_eval:
        with kiwi_bridge.KiwiSession(device="cpu") as session:
            result = session.eval("+/1 2 3")
        if result.status != "ok" or result.text != "6":
            raise RuntimeError(f"unexpected Kiwi eval result: {result}")
        print("eval: +/1 2 3 -> 6")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
