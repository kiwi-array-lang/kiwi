from __future__ import annotations

import json
import os
import re
from typing import Any

from ipykernel.kernelbase import Kernel

from . import __version__
from .binding import DEVICE_ENV_VAR, LIB_ENV_VAR, KiwiSession
from .execution import CellExecutionError, CellOutput, execute_cell, simple_is_complete

SYMBOL_DOCS = {
    "exp": "exp[x] applies the elementwise exponential.",
    "grad": (
        "grad[f] returns a function that differentiates scalar-returning f "
        "with respect to its first argument."
    ),
    "log": "log[x] applies the elementwise natural logarithm.",
    "sigmoid": "sigmoid[x] applies the elementwise logistic sigmoid.",
    "tanh": "tanh[x] applies the elementwise hyperbolic tangent.",
    "valuegrad": (
        "valuegrad[f] returns a function that yields both the scalar result "
        "of f and its gradient."
    ),
}
COMPLETION_WORDS = tuple(SYMBOL_DOCS)


class KiwiKernel(Kernel):
    implementation = "kiwilang-jupyter-kernel"
    implementation_version = __version__
    language = "kiwi"
    language_version = "0.2"
    banner = "Kiwi 0.2 kernel"
    language_info = {
        "name": "kiwi",
        "mimetype": "text/x-kiwi",
        "file_extension": ".k",
        "pygments_lexer": "text",
    }

    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)
        device = os.environ.get(DEVICE_ENV_VAR, "auto")
        library_path = os.environ.get(LIB_ENV_VAR)
        self._session = KiwiSession(device=device, library_path=library_path)

    def do_execute(
        self,
        code: str,
        silent: bool,
        store_history: bool = True,
        user_expressions: Any = None,
        allow_stdin: bool = False,
    ) -> dict[str, Any]:
        del store_history, allow_stdin
        try:
            outputs = execute_cell(self._session, code)
        except CellExecutionError as exc:
            if not silent:
                self.send_response(
                    self.iopub_socket,
                    "error",
                    {
                        "ename": "KiwiError",
                        "evalue": str(exc),
                        "traceback": [],
                    },
                )
            return {
                "status": "error",
                "ename": "KiwiError",
                "evalue": str(exc),
                "traceback": [],
            }

        if not silent:
            for output in outputs[:-1]:
                self.send_response(
                    self.iopub_socket,
                    "stream",
                    {
                        "name": "stdout",
                        "text": output.text + "\n",
                    },
                )

            if outputs:
                last = outputs[-1]
                self.send_response(
                    self.iopub_socket,
                    "execute_result",
                    {
                        "execution_count": self.execution_count,
                        "data": _display_data_for_output(last),
                        "metadata": {"kiwi_autograd_path": last.autograd_path},
                    },
                )

        return {
            "status": "ok",
            "execution_count": self.execution_count,
            "payload": [],
            "user_expressions": {},
        }

    def do_complete(self, code: str, cursor_pos: int) -> dict[str, Any]:
        prefix = _completion_prefix(code[:cursor_pos])
        matches = [word for word in COMPLETION_WORDS if prefix and word.startswith(prefix)]
        return {
            "matches": matches,
            "cursor_start": cursor_pos - len(prefix),
            "cursor_end": cursor_pos,
            "metadata": {},
            "status": "ok",
        }

    def do_inspect(
        self,
        code: str,
        cursor_pos: int,
        detail_level: int = 0,
        omit_sections: Any = (),
    ) -> dict[str, Any]:
        del detail_level, omit_sections
        symbol = _symbol_at_cursor(code, cursor_pos)
        if symbol is None:
            return {
                "status": "ok",
                "found": False,
                "data": {},
                "metadata": {},
            }
        doc = SYMBOL_DOCS.get(symbol)
        if doc is None:
            return {
                "status": "ok",
                "found": False,
                "data": {},
                "metadata": {},
            }
        return {
            "status": "ok",
            "found": True,
            "data": {"text/plain": doc},
            "metadata": {},
        }

    def do_is_complete(self, code: str) -> dict[str, Any]:
        status = simple_is_complete(code)
        reply = {"status": status}
        if status == "incomplete":
            reply["indent"] = " "
        return reply

    def do_shutdown(self, restart: bool) -> dict[str, Any]:
        self._session.close()
        return {"status": "ok", "restart": restart}


def _completion_prefix(code: str) -> str:
    match = re.search(r"[A-Za-z_][A-Za-z0-9_]*$", code)
    if match is None:
        return ""
    return match.group(0)


def _symbol_at_cursor(code: str, cursor_pos: int) -> str | None:
    for match in re.finditer(r"[A-Za-z_][A-Za-z0-9_]*", code):
        if match.start() <= cursor_pos <= match.end():
            return match.group(0)
    return None


def _display_data_for_output(output: CellOutput) -> dict[str, Any]:
    data: dict[str, Any] = {"text/plain": output.text}
    if output.display_mime is None or output.display_data is None:
        return data
    try:
        data[output.display_mime] = json.loads(output.display_data)
    except json.JSONDecodeError:
        pass
    return data
