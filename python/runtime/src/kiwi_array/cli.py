from __future__ import annotations

import os
import subprocess
import sys

from . import bridge


def _launcher_environment() -> dict[str, str]:
    env = os.environ.copy()
    library_var = bridge.runtime_library_env_var()
    if library_var is None:
        return env
    library_dir = bridge.runtime_library_search_dir()
    existing = env.get(library_var)
    env[library_var] = str(library_dir) if not existing else f"{library_dir}{os.pathsep}{existing}"
    return env


def main() -> int:
    try:
        cli = bridge.find_cli_path()
    except FileNotFoundError as exc:
        print(exc, file=sys.stderr)
        return 1

    argv = [str(cli), *sys.argv[1:]]
    if hasattr(os, "execve"):
        os.execve(str(cli), argv, _launcher_environment())
    completed = subprocess.run(argv, env=_launcher_environment())
    return int(completed.returncode)


if __name__ == "__main__":
    raise SystemExit(main())
