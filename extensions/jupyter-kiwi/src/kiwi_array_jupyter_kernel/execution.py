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
        line = sanitize_line(raw_line)
        if line is None:
            continue
        yield line_no, line


def sanitize_line(raw_line: str) -> str | None:
    line = raw_line.strip(" \t\r")
    if not line or line.startswith("/"):
        return None

    for index, ch in enumerate(line):
        if ch == "/" and index > 0 and line[index - 1].isspace():
            trimmed = line[:index].rstrip(" \t")
            return trimmed or None
    return line


def iter_executable_statements(code: str) -> Iterator[tuple[int, str]]:
    pending: list[str] = []
    start_line = 0
    depth = ScriptDepth()

    for line_no, line in iter_executable_lines(code):
        if not pending:
            start_line = line_no
            depth = ScriptDepth()
        pending.append(line)
        if not update_script_depth(line, depth):
            raise CellExecutionError(line_no, "parse")
        if not depth.is_zero():
            continue
        yield start_line, "\n".join(pending)
        pending.clear()

    if pending:
        raise CellExecutionError(start_line, "parse")


def execute_cell(session: SessionProtocol, code: str) -> list[CellOutput]:
    outputs: list[CellOutput] = []
    for line_no, statement in iter_executable_statements(code):
        result = session.eval(statement)
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


@dataclass
class ScriptDepth:
    paren: int = 0
    bracket: int = 0
    brace: int = 0

    def is_zero(self) -> bool:
        return self.paren == 0 and self.bracket == 0 and self.brace == 0


def update_script_depth(line: str, depth: ScriptDepth) -> bool:
    index = 0
    while index < len(line):
        ch = line[index]
        if ch == '"':
            index += 1
            while index < len(line) and line[index] != '"':
                index += 1
            if index >= len(line):
                return False
        elif ch == "(":
            depth.paren += 1
        elif ch == ")":
            if depth.paren == 0:
                return False
            depth.paren -= 1
        elif ch == "[":
            depth.bracket += 1
        elif ch == "]":
            if depth.bracket == 0:
                return False
            depth.bracket -= 1
        elif ch == "{":
            depth.brace += 1
        elif ch == "}":
            if depth.brace == 0:
                return False
            depth.brace -= 1
        index += 1
    return True


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
