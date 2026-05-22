from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys

import pytest

RUNTIME_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_SRC = RUNTIME_ROOT / "src"
if str(RUNTIME_SRC) not in sys.path:
    sys.path.insert(0, str(RUNTIME_SRC))

from kiwi_array.notebook import (
    CellOutput,
    KiwiNotebookError,
    SmokeCheck,
    display_bundle_for_output,
    execute_cell,
    format_info_text,
    format_smoke_text,
    iter_executable_lines,
    load_ipython_extension,
    run_smoke,
    vegalite_html,
)


@dataclass
class FakeResult:
    status: str = "ok"
    echoed: bool = True
    text: str | None = "1"
    autograd_path: str = "none"
    display_mime: str | None = None
    display_data: str | None = None


class FakeSession:
    def __init__(self, results: list[FakeResult]) -> None:
        self.results = list(results)
        self.sources: list[str] = []

    def eval(self, source: str) -> FakeResult:
        self.sources.append(source)
        return self.results.pop(0)

    def close(self) -> None:
        pass


class FakeMlxSession(FakeSession):
    def __init__(self, results: list[FakeResult]) -> None:
        super().__init__(results)
        self.mlx_globals: list[tuple[str, tuple[int, ...]]] = []

    def set_global_mlx_float_array(self, name: str, data, dims) -> None:
        del data
        self.mlx_globals.append((name, tuple(dims)))


def test_iter_executable_lines_skips_blank_and_comment_lines() -> None:
    assert list(iter_executable_lines("\n/a comment\nx:1\n  \n+/x\n")) == [(3, "x:1"), (5, "+/x")]


def test_execute_cell_collects_echoed_outputs() -> None:
    session = FakeSession([FakeResult(echoed=False, text=None), FakeResult(text="6")])

    outputs = execute_cell(session, "x:1 2 3\n+/x")

    assert session.sources == ["x:1 2 3", "+/x"]
    assert outputs == [CellOutput(line_no=2, text="6", autograd_path="none")]


def test_execute_cell_raises_on_error_status() -> None:
    session = FakeSession([FakeResult(status="parse_error")])

    with pytest.raises(KiwiNotebookError, match=r"line 1: !parse_error"):
        execute_cell(session, "1+")


def test_display_bundle_includes_vegalite_mime_and_html_fallback() -> None:
    spec = {"$schema": "https://vega.github.io/schema/vega-lite/v5.json", "mark": "bar"}
    output = CellOutput(
        line_no=1,
        text='{"mark":"bar"}',
        autograd_path="none",
        display_mime="application/vnd.vegalite.v5+json",
        display_data='{"$schema":"https://vega.github.io/schema/vega-lite/v5.json","mark":"bar"}',
    )

    bundle = display_bundle_for_output(output)

    assert bundle["application/vnd.vegalite.v5+json"] == spec
    assert "vegaEmbed" in str(bundle["text/html"])
    assert '"theme"' not in str(bundle["text/html"])


def test_vegalite_html_uses_theme_from_environment(monkeypatch) -> None:
    monkeypatch.setenv("KIWI_VEGALITE_THEME", "dark")

    html = vegalite_html({"mark": "bar"})

    assert '"theme":"dark"' in html


def test_format_info_text_aligns_labels() -> None:
    assert format_info_text([("a", "1"), ("long", "2")]) == "   a: 1\nlong: 2"


def test_run_smoke_reports_basic_checks() -> None:
    session = FakeSession(
        [
            FakeResult(text="2"),
            FakeResult(text="6"),
            FakeResult(text="2 4 6"),
        ]
    )

    checks = run_smoke(session)

    assert session.sources == ["1+1", "+/1 2 3", "grad[{+/(x*x)}][1 2 3]"]
    assert checks == [
        SmokeCheck(name="scalar", ok=True, detail="2"),
        SmokeCheck(name="vector", ok=True, detail="6"),
        SmokeCheck(name="grad", ok=True, detail="2 4 6"),
    ]
    assert "scalar: ok 2" in format_smoke_text(checks)


def test_run_smoke_can_check_mlx_global_path() -> None:
    session = FakeMlxSession(
        [
            FakeResult(text="2"),
            FakeResult(text="6"),
            FakeResult(text="2 4 6"),
            FakeResult(text="2 4 6"),
        ]
    )

    checks = run_smoke(session, include_mlx=True)

    assert session.mlx_globals == [("kx", (3,))]
    assert checks[-1] == SmokeCheck(name="mlx_global", ok=True, detail="2 4 6")


def test_load_extension_registers_k_and_kiwi_magics() -> None:
    pytest.importorskip("IPython")
    from IPython.core.interactiveshell import InteractiveShell

    shell = InteractiveShell()
    load_ipython_extension(shell)

    assert "k" in shell.magics_manager.magics["line"]
    assert "k" in shell.magics_manager.magics["cell"]
    assert "kiwi" in shell.magics_manager.magics["line"]
    assert "kiwi" in shell.magics_manager.magics["cell"]
    assert "kinfo" in shell.magics_manager.magics["line"]
    assert "ksmoke" in shell.magics_manager.magics["line"]
