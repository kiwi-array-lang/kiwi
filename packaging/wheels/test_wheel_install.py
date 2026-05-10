#!/usr/bin/env python3

from __future__ import annotations

import importlib


def main() -> int:
    kiwi_bridge = importlib.import_module("kiwi_bridge")
    jupyter_kernel = importlib.import_module("kiwi_jupyter_kernel")
    kiwilang = importlib.import_module("kiwilang")
    print(f"kiwilang {kiwilang.__version__}")
    print(f"kiwi_jupyter_kernel {jupyter_kernel.__version__}")
    print(f"bridge candidates: {kiwi_bridge.default_library_candidates()}")
    print(f"bridge library: {kiwi_bridge.find_library_path()}")
    with kiwi_bridge.KiwiSession(device="cpu") as session:
        result = session.eval("+/1 2 3")
    if result.status != "ok" or result.text != "6":
        raise RuntimeError(f"unexpected Kiwi eval result: {result}")
    print("eval: +/1 2 3 -> 6")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
