from __future__ import annotations

from dataclasses import dataclass
from typing import Iterator, Protocol

from .binding import KiwiEvalResult


class SessionProtocol(Protocol):
    def eval(self, source: str) -> KiwiEvalResult:
        ...


@dataclass(frozen=True)
class CellOutput:
    line_no: int
    text: str
    autograd_path: str
    display_mime: str | None = None
    display_data: str | None = None


class CellExecutionError(RuntimeError):
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
            raise CellExecutionError(line_no, result.status)
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


def simple_is_complete(code: str) -> str:
    stack: list[str] = []
    in_string = False
    pairs = {
        "(": ")",
        "[": "]",
        "{": "}",
    }

    for raw_line in code.splitlines():
        stripped = raw_line.lstrip(" \t")
        if stripped.startswith("/"):
            continue

        for ch in raw_line:
            if ch == '"':
                in_string = not in_string
                continue
            if in_string:
                continue
            if ch in "([{":
                stack.append(ch)
                continue
            if ch in ")]}":
                if not stack:
                    return "invalid"
                opener = stack.pop()
                if pairs[opener] != ch:
                    return "invalid"

    if in_string or stack:
        return "incomplete"
    return "complete"
