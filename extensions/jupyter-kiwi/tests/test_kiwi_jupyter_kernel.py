from __future__ import annotations

import os
from pathlib import Path
import sys
import uuid

from jupyter_client import KernelManager
import pytest

JUPYTER_ROOT = Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = JUPYTER_ROOT.parents[1]
KIWI_ROOT = (
    WORKSPACE_ROOT
    if (WORKSPACE_ROOT / "src" / "kiwi_bridge.zig").is_file()
    else WORKSPACE_ROOT / "implementations" / "kiwi-zig-main"
)
PACKAGE_SRC = JUPYTER_ROOT / "src"
RUNTIME_SRC = KIWI_ROOT / "python" / "runtime" / "src"
for src in (PACKAGE_SRC, RUNTIME_SRC):
    if str(src) not in sys.path:
        sys.path.insert(0, str(src))

from kiwi_array_jupyter_kernel.binding import (
    LEGACY_LIB_ENV_VAR,
    LIB_ENV_VAR,
    KiwiEvalResult,
    experiment_root,
    find_library_path,
    implementation_root,
    platform_library_name,
    runtime_library_env_var,
    runtime_library_search_dir,
)
from kiwi_array_jupyter_kernel.execution import (
    CellExecutionError,
    CellOutput,
    execute_cell,
    iter_executable_lines,
    iter_executable_statements,
    simple_is_complete,
)
from kiwi_array_jupyter_kernel.install import build_bridge, build_kernel_spec, find_logo_path, install_kernel, write_kernel_logos
from kiwi_array_jupyter_kernel.kernel import _display_data_for_output


class FakeSession:
    def __init__(self, mapping):
        self.mapping = mapping
        self.calls = []

    def eval(self, source: str) -> KiwiEvalResult:
        self.calls.append(source)
        return self.mapping[source]


def test_iter_executable_lines_skips_blank_lines_and_full_line_comments():
    code = "\n/ comment\na:1 2 3 / inline comment\n  / spaced comment\n+/a\r\n"
    assert list(iter_executable_lines(code)) == [(3, "a:1 2 3"), (5, "+/a")]


def test_iter_executable_statements_groups_balanced_multiline_source():
    code = "\n/ comment\nf:{\n x+1 / inline comment with }\n}\n\nf 3\n"
    assert list(iter_executable_statements(code)) == [
        (3, "f:{\nx+1\n}"),
        (7, "f 3"),
    ]


def test_execute_cell_returns_echoed_outputs_in_order():
    session = FakeSession(
        {
            "a:1 2 3": KiwiEvalResult(status="ok", echoed=False, autograd_path="none", text=None),
            "+/a": KiwiEvalResult(status="ok", echoed=True, autograd_path="none", text="6"),
            "grad[{x*x}][3]": KiwiEvalResult(status="ok", echoed=True, autograd_path="mlx", text="6"),
        }
    )

    outputs = execute_cell(session, "a:1 2 3\n+/a\ngrad[{x*x}][3]\n")

    assert session.calls == ["a:1 2 3", "+/a", "grad[{x*x}][3]"]
    assert [(item.line_no, item.text, item.autograd_path) for item in outputs] == [
        (2, "6", "none"),
        (3, "6", "mlx"),
    ]


def test_execute_cell_sends_multiline_statements_as_one_eval():
    session = FakeSession(
        {
            "f:{\nx+1\n}": KiwiEvalResult(status="ok", echoed=False, autograd_path="none", text=None),
            "f 3": KiwiEvalResult(status="ok", echoed=True, autograd_path="none", text="4"),
        }
    )

    outputs = execute_cell(session, "f:{\n x+1\n}\nf 3\n")

    assert session.calls == ["f:{\nx+1\n}", "f 3"]
    assert [(item.line_no, item.text) for item in outputs] == [(4, "4")]


def test_execute_cell_strips_inline_comments_before_eval():
    session = FakeSession(
        {
            "f:{\nx+1\n}": KiwiEvalResult(status="ok", echoed=False, autograd_path="none", text=None),
            "f 3": KiwiEvalResult(status="ok", echoed=True, autograd_path="none", text="4"),
        }
    )

    outputs = execute_cell(session, "f:{\n x+1 / inline comment\n}\nf 3 / call\n")

    assert session.calls == ["f:{\nx+1\n}", "f 3"]
    assert [(item.line_no, item.text) for item in outputs] == [(4, "4")]


def test_execute_cell_reports_multiline_statement_start_line_on_error():
    session = FakeSession(
        {
            "f:{\nx+1\n}": KiwiEvalResult(status="parse", echoed=False, autograd_path="none", text=None),
        }
    )

    with pytest.raises(CellExecutionError) as exc_info:
        execute_cell(session, "\n\nf:{\n x+1\n}\n")

    assert exc_info.value.line_no == 3
    assert exc_info.value.status == "parse"


def test_execute_cell_preserves_display_bundle():
    display_json = '{"$schema":"https://vega.github.io/schema/vega-lite/v5.json"}'
    session = FakeSession(
        {
            "plot": KiwiEvalResult(
                status="ok",
                echoed=True,
                autograd_path="none",
                text=f'"{display_json}"',
                display_mime="application/vnd.vegalite.v5+json",
                display_data=display_json,
            ),
        }
    )

    outputs = execute_cell(session, "plot")

    assert outputs == [
        CellOutput(
            line_no=1,
            text=f'"{display_json}"',
            autograd_path="none",
            display_mime="application/vnd.vegalite.v5+json",
            display_data=display_json,
        )
    ]


def test_display_data_for_output_parses_json_mime_payload():
    output = CellOutput(
        line_no=1,
        text='"{}"',
        autograd_path="none",
        display_mime="application/vnd.vegalite.v5+json",
        display_data='{"$schema":"https://vega.github.io/schema/vega-lite/v5.json"}',
    )

    data = _display_data_for_output(output)

    assert data["text/plain"] == '"{}"'
    assert data["application/vnd.vegalite.v5+json"]["$schema"].endswith("/vega-lite/v5.json")


def test_execute_cell_reports_error_line_number():
    session = FakeSession(
        {
            "a:5": KiwiEvalResult(status="ok", echoed=False, autograd_path="none", text=None),
            "a+b": KiwiEvalResult(status="name", echoed=False, autograd_path="none", text=None),
        }
    )

    try:
        execute_cell(session, "a:5\na+b\n")
    except CellExecutionError as exc:
        assert exc.line_no == 2
        assert exc.status == "name"
        assert str(exc) == "line 2: !name"
    else:  # pragma: no cover - defensive
        raise AssertionError("expected CellExecutionError")


def test_simple_is_complete_tracks_basic_delimiter_balance():
    assert simple_is_complete("grad[{x*x}][3]") == "complete"
    assert simple_is_complete("grad[{x*x}][3") == "incomplete"
    assert simple_is_complete("{[x;y]\n x+y") == "incomplete"
    assert simple_is_complete('/ comment only\n"abc') == "incomplete"
    assert simple_is_complete(")]") == "invalid"
    assert simple_is_complete("{]") == "invalid"


def test_build_kernel_spec_uses_module_entrypoint(monkeypatch):
    monkeypatch.delenv("PYTHONPATH", raising=False)
    spec = build_kernel_spec(display_name="Kiwi Test", device="cpu", python_executable="python")

    expected_env = {
        "KIWI_JUPYTER_DEVICE": "cpu",
    }
    env_var = runtime_library_env_var()
    if env_var is not None:
        expected_env[env_var] = str(runtime_library_search_dir())

    assert spec["argv"] == ["python", "-m", "kiwi_array_jupyter_kernel", "-f", "{connection_file}"]
    assert spec["display_name"] == "Kiwi Test"
    assert spec["language"] == "kiwi"
    assert spec["env"] == expected_env


def test_build_kernel_spec_can_pin_bridge_library(tmp_path, monkeypatch):
    monkeypatch.delenv("PYTHONPATH", raising=False)
    library_path = tmp_path / platform_library_name("kiwi_bridge")
    spec = build_kernel_spec(
        display_name="Kiwi Test",
        device="cpu",
        python_executable="python",
        library_path=str(library_path),
    )

    expected_env = {
        "KIWI_JUPYTER_DEVICE": "cpu",
        "KIWI_BRIDGE_LIB": str(library_path),
    }
    env_var = runtime_library_env_var()
    if env_var is not None:
        expected_env[env_var] = str(runtime_library_search_dir())

    assert spec["env"] == expected_env


def test_bridge_helpers_point_at_main_bridge():
    assert experiment_root() == JUPYTER_ROOT
    assert implementation_root() == KIWI_ROOT
    assert platform_library_name("kiwi_bridge").startswith("libkiwi_bridge")


def test_find_library_path_accepts_legacy_bridge_env_alias(tmp_path, monkeypatch):
    legacy_path = tmp_path / platform_library_name("kiwi_bridge")
    legacy_path.write_bytes(b"")
    monkeypatch.delenv(LIB_ENV_VAR, raising=False)
    monkeypatch.setenv(LEGACY_LIB_ENV_VAR, str(legacy_path))

    assert find_library_path() == legacy_path


def test_logo_helpers_find_current_kernel_icon_and_copy_kernel_assets(tmp_path):
    logo_path = find_logo_path()
    assert logo_path is not None
    assert logo_path == JUPYTER_ROOT / "src" / "kiwi_array_jupyter_kernel" / "assets" / "kernel-logo.png"

    write_kernel_logos(tmp_path)

    assert (tmp_path / "logo-32x32.png").read_bytes() == logo_path.read_bytes()
    assert (tmp_path / "logo-64x64.png").read_bytes() == logo_path.read_bytes()


@pytest.fixture(scope="session")
def installed_kernel_spec(tmp_path_factory):
    build_bridge()
    prefix = tmp_path_factory.mktemp("kiwi-jupyter-kernel")
    name = f"kiwi_test_{uuid.uuid4().hex[:8]}"
    location = Path(
        install_kernel(
            name=name,
            prefix=str(prefix),
            user=False,
            skip_build=True,
        )
    )
    return {
        "name": name,
        "jupyter_path": str(prefix / "share" / "jupyter"),
        "kernel_json": location / "kernel.json",
    }


@pytest.fixture
def kernel_client(installed_kernel_spec):
    old_jupyter_path = os.environ.get("JUPYTER_PATH")
    os.environ["JUPYTER_PATH"] = installed_kernel_spec["jupyter_path"]

    km = KernelManager(kernel_name=installed_kernel_spec["name"])
    km.start_kernel()
    client = km.blocking_client()
    client.start_channels()
    client.wait_for_ready(timeout=30)
    try:
        yield client
    finally:
        client.stop_channels()
        km.shutdown_kernel(now=True)
        if old_jupyter_path is None:
            os.environ.pop("JUPYTER_PATH", None)
        else:
            os.environ["JUPYTER_PATH"] = old_jupyter_path


def _shell_reply(client, msg_id: str):
    while True:
        reply = client.get_shell_msg(timeout=30)
        if reply["parent_header"].get("msg_id") == msg_id:
            return reply


def _iopub_messages(client, msg_id: str):
    messages = []
    while True:
        message = client.get_iopub_msg(timeout=30)
        if message["parent_header"].get("msg_id") != msg_id:
            continue
        messages.append(message)
        if (
            message["header"]["msg_type"] == "status"
            and message["content"].get("execution_state") == "idle"
        ):
            return messages


def test_install_kernel_writes_bridge_path_to_kernel_spec(installed_kernel_spec):
    kernel_json = installed_kernel_spec["kernel_json"].read_text()
    assert str(find_library_path()) in kernel_json
    assert LIB_ENV_VAR in kernel_json


def test_install_kernel_writes_logo_assets(installed_kernel_spec):
    kernel_dir = installed_kernel_spec["kernel_json"].parent
    assert (kernel_dir / "logo-32x32.png").exists()
    assert (kernel_dir / "logo-64x64.png").exists()


def test_kernel_executes_cells_over_jupyter_protocol(kernel_client):
    msg_id = kernel_client.execute("a:1 2 3\n+/a")
    reply = _shell_reply(kernel_client, msg_id)
    messages = _iopub_messages(kernel_client, msg_id)

    assert reply["content"]["status"] == "ok"
    results = [msg for msg in messages if msg["header"]["msg_type"] == "execute_result"]
    assert len(results) == 1
    assert results[0]["content"]["data"]["text/plain"] == "6"


def test_kernel_executes_multiline_definitions_over_jupyter_protocol(kernel_client):
    msg_id = kernel_client.execute("f:{\n x+1 / inline comment\n}\nf 3 / call")
    reply = _shell_reply(kernel_client, msg_id)
    messages = _iopub_messages(kernel_client, msg_id)

    assert reply["content"]["status"] == "ok"
    results = [msg for msg in messages if msg["header"]["msg_type"] == "execute_result"]
    assert len(results) == 1
    assert results[0]["content"]["data"]["text/plain"] == "4"


def test_kernel_emits_vegalite_mime_over_jupyter_protocol(kernel_client):
    code = (
        "`j@(\"$schema\";\"data\";\"mark\";\"encoding\")!"
        "(\"https://vega.github.io/schema/vega-lite/v5.json\";"
        "(,\"values\")!(,+(`x`y!(1 2;3 4)));"
        "`point;"
        "`x`y!(`field`type!(\"x\";\"quantitative\");`field`type!(\"y\";\"quantitative\")))"
    )
    msg_id = kernel_client.execute(code)
    reply = _shell_reply(kernel_client, msg_id)
    messages = _iopub_messages(kernel_client, msg_id)

    assert reply["content"]["status"] == "ok"
    results = [msg for msg in messages if msg["header"]["msg_type"] == "execute_result"]
    assert len(results) == 1
    data = results[0]["content"]["data"]
    assert "application/vnd.vegalite.v5+json" in data
    assert data["application/vnd.vegalite.v5+json"]["mark"] == "point"
    assert data["application/vnd.vegalite.v5+json"]["data"]["values"] == [
        {"x": 1, "y": 3},
        {"x": 2, "y": 4},
    ]


def test_kernel_reports_errors_over_jupyter_protocol(kernel_client):
    msg_id = kernel_client.execute("a+b")
    reply = _shell_reply(kernel_client, msg_id)
    messages = _iopub_messages(kernel_client, msg_id)

    assert reply["content"]["status"] == "error"
    assert reply["content"]["evalue"] == "line 1: !name"
    errors = [msg for msg in messages if msg["header"]["msg_type"] == "error"]
    assert len(errors) == 1
    assert errors[0]["content"]["evalue"] == "line 1: !name"


def test_kernel_inspect_returns_symbol_docs(kernel_client):
    msg_id = kernel_client.inspect("grad", cursor_pos=4)
    reply = _shell_reply(kernel_client, msg_id)

    assert reply["content"]["status"] == "ok"
    assert reply["content"]["found"] is True
    assert "grad[f]" in reply["content"]["data"]["text/plain"]


def test_kernel_is_complete_marks_invalid_delimiters(kernel_client):
    msg_id = kernel_client.is_complete(")]")
    reply = _shell_reply(kernel_client, msg_id)

    assert reply["content"]["status"] == "invalid"
