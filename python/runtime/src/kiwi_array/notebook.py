from __future__ import annotations

import json
import os
import platform
import subprocess
import sys
import uuid
from dataclasses import dataclass
from typing import Iterator, Protocol

from kiwi_array.bridge import KiwiEvalResult, KiwiSession, find_library_path, runtime_library_search_dir

from . import __version__


class SessionProtocol(Protocol):
    def eval(self, source: str) -> KiwiEvalResult:
        ...

    def close(self) -> None:
        ...


@dataclass(frozen=True)
class CellOutput:
    line_no: int
    text: str
    autograd_path: str
    display_mime: str | None = None
    display_data: str | None = None


@dataclass(frozen=True)
class SmokeCheck:
    name: str
    ok: bool
    detail: str


class KiwiNotebookError(RuntimeError):
    def __init__(self, line_no: int, status: str) -> None:
        self.line_no = line_no
        self.status = status
        super().__init__(f"line {line_no}: !{status}")


def iter_executable_lines(code: str) -> Iterator[tuple[int, str]]:
    for line_no, raw_line in enumerate(code.splitlines(), start=1):
        line = raw_line.rstrip("\r")
        trimmed = line.strip(" \t")
        if not trimmed or trimmed.startswith("/"):
            continue
        yield line_no, line


def execute_cell(session: SessionProtocol, code: str) -> list[CellOutput]:
    outputs: list[CellOutput] = []
    for line_no, line in iter_executable_lines(code):
        result = session.eval(line)
        if result.status != "ok":
            raise KiwiNotebookError(line_no, result.status)
        if result.echoed and result.text is not None:
            outputs.append(
                CellOutput(
                    line_no=line_no,
                    text=result.text,
                    autograd_path=result.autograd_path,
                    display_mime=result.display_mime,
                    display_data=result.display_data,
                )
            )
    return outputs


def display_bundle_for_output(output: CellOutput) -> dict[str, object]:
    bundle: dict[str, object] = {"text/plain": output.text}
    if output.display_mime is None or output.display_data is None:
        return bundle
    try:
        payload = json.loads(output.display_data)
    except json.JSONDecodeError:
        return bundle
    bundle[output.display_mime] = payload
    if "vegalite" in output.display_mime:
        bundle["text/html"] = vegalite_html(payload)
    return bundle


def vegalite_embed_options() -> dict[str, object]:
    options: dict[str, object] = {"actions": False, "renderer": "canvas"}
    theme = os.environ.get("KIWI_VEGALITE_THEME", "").strip()
    if theme and theme.lower() not in {"default", "none"}:
        options["theme"] = theme
    return options


def vegalite_html(spec: object) -> str:
    element_id = f"kiwi-vegalite-{uuid.uuid4().hex}"
    spec_json = json.dumps(spec, separators=(",", ":"))
    options_json = json.dumps(vegalite_embed_options(), separators=(",", ":"))
    return f"""
<div id="{element_id}"></div>
<script src="https://cdn.jsdelivr.net/npm/vega@5"></script>
<script src="https://cdn.jsdelivr.net/npm/vega-lite@5"></script>
<script src="https://cdn.jsdelivr.net/npm/vega-embed@6"></script>
<script>
(function() {{
  const spec = {spec_json};
  const render = function() {{
    if (!window.vegaEmbed) {{
      document.getElementById("{element_id}").textContent = {json.dumps("Vega-Embed failed to load.")};
      return;
    }}
    window.vegaEmbed("#{element_id}", spec, {options_json});
  }};
  render();
}})();
</script>
"""


def _safe_value(label: str, value_fn) -> tuple[str, str]:
    try:
        value = str(value_fn())
    except Exception as exc:  # pragma: no cover - defensive diagnostic path
        value = f"!{type(exc).__name__}: {exc}"
    return label, value


def _nvidia_smi_summary() -> str:
    if platform.system() != "Linux":
        return "not linux"
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,driver_version,memory.total",
                "--format=csv,noheader,nounits",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "not found"
    if result.returncode != 0:
        message = (result.stderr or result.stdout).strip()
        return message or f"exit {result.returncode}"
    return result.stdout.strip() or "no gpu"


def collect_info() -> list[tuple[str, str]]:
    return [
        ("kiwi-array", __version__),
        ("python", sys.version.split()[0]),
        ("platform", platform.platform()),
        _safe_value("bridge", find_library_path),
        _safe_value("runtime_libs", runtime_library_search_dir),
        ("device_env", os.environ.get("KIWI_JUPYTER_DEVICE", "auto")),
        ("vegalite_theme", os.environ.get("KIWI_VEGALITE_THEME", "default")),
        ("nvidia_smi", _nvidia_smi_summary()),
    ]


def format_info_text(info: list[tuple[str, str]]) -> str:
    width = max((len(label) for label, _ in info), default=0)
    return "\n".join(f"{label.rjust(width)}: {value}" for label, value in info)


def run_smoke(session: SessionProtocol, include_mlx: bool = False) -> list[SmokeCheck]:
    checks: list[SmokeCheck] = []
    for name, source, expected in [
        ("scalar", "1+1", "2"),
        ("vector", "+/1 2 3", "6"),
        ("grad", "grad[{+/(x*x)}][1 2 3]", "2 4 6"),
    ]:
        result = session.eval(source)
        ok = result.status == "ok" and result.text == expected
        detail = result.text if result.status == "ok" and result.text is not None else f"!{result.status}"
        checks.append(SmokeCheck(name=name, ok=ok, detail=detail))

    if include_mlx:
        setter = getattr(session, "set_global_mlx_float_array", None)
        if setter is None:
            checks.append(SmokeCheck(name="mlx_global", ok=False, detail="native bridge lacks MLX setter"))
            return checks
        try:
            setter("kx", [1.0, 2.0, 3.0], (3,))
            result = session.eval("grad[{+/(x*x)}][kx]")
            ok = result.status == "ok" and result.text == "2 4 6"
            detail = result.text if result.status == "ok" and result.text is not None else f"!{result.status}"
            checks.append(SmokeCheck(name="mlx_global", ok=ok, detail=detail))
        except Exception as exc:
            checks.append(SmokeCheck(name="mlx_global", ok=False, detail=f"!{type(exc).__name__}: {exc}"))

    return checks


def format_smoke_text(checks: list[SmokeCheck]) -> str:
    width = max((len(check.name) for check in checks), default=0)
    lines = []
    for check in checks:
        status = "ok" if check.ok else "error"
        lines.append(f"{check.name.rjust(width)}: {status} {check.detail}")
    return "\n".join(lines)


def load_ipython_extension(ipython) -> None:
    from IPython.core.magic import Magics, line_cell_magic, line_magic, magics_class
    from IPython.display import display

    @magics_class
    class KiwiMagics(Magics):
        def __init__(self, shell) -> None:
            super().__init__(shell)
            self._session: KiwiSession | None = None

        def _kiwi_session(self) -> KiwiSession:
            if self._session is None:
                device = os.environ.get("KIWI_JUPYTER_DEVICE", "auto")
                library_path = os.environ.get("KIWI_BRIDGE_LIB")
                self._session = KiwiSession(device=device, library_path=library_path)
            return self._session

        def _reset(self) -> None:
            if self._session is not None:
                self._session.close()
                self._session = None

        def _run(self, line: str, cell: str | None) -> None:
            if cell is None and line.strip() in {"--reset", "-r"}:
                self._reset()
                return
            code = line if cell is None else cell
            outputs = execute_cell(self._kiwi_session(), code)
            for output in outputs:
                display(
                    display_bundle_for_output(output),
                    raw=True,
                    metadata={"kiwi_autograd_path": output.autograd_path},
                )

        @line_cell_magic
        def kiwi(self, line: str, cell: str | None = None) -> None:
            self._run(line, cell)

        @line_cell_magic
        def k(self, line: str, cell: str | None = None) -> None:
            self._run(line, cell)

        @line_magic
        def kinfo(self, line: str) -> None:
            del line
            print(format_info_text(collect_info()))

        @line_magic
        def ksmoke(self, line: str) -> None:
            flags = set(line.split())
            include_mlx = bool(flags & {"--mlx", "--gpu"})
            print(format_smoke_text(run_smoke(self._kiwi_session(), include_mlx=include_mlx)))

    ipython.register_magics(KiwiMagics)


def unload_ipython_extension(ipython) -> None:
    del ipython
