"use strict";

const fs = require("fs");
const path = require("path");
const vscode = require("vscode");

let terminal;

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("kiwi.startRepl", startRepl),
    vscode.commands.registerCommand("kiwi.evalSelectionOrLine", evalSelectionOrStatement),
    vscode.commands.registerCommand("kiwi.evalBlock", evalBlock),
    vscode.commands.registerCommand("kiwi.evalFile", evalFile),
    vscode.commands.registerCommand("kiwi.resetSession", resetSession),
  );
}

function deactivate() {
  terminal = undefined;
}

function config() {
  return vscode.workspace.getConfiguration("kiwi");
}

function ensureTerminal() {
  if (!terminal || terminal.exitStatus !== undefined) {
    const binaryPath = config().get("binaryPath", "kiwi");
    terminal = vscode.window.createTerminal({
      name: "kiwi",
      shellPath: binaryPath,
      shellArgs: config().get("replArgs", []),
      cwd: configuredWorkingDirectory(),
      env: configuredEnvironment(binaryPath),
    });
  }
  terminal.show();
  return terminal;
}

function startRepl() {
  ensureTerminal();
}

function resetSession() {
  if (terminal) terminal.dispose();
  terminal = undefined;
  ensureTerminal();
}

function activeEditor() {
  const editor = vscode.window.activeTextEditor;
  if (!editor) {
    vscode.window.showInformationMessage("No active editor.");
    return undefined;
  }
  return editor;
}

function evalSelectionOrStatement() {
  const editor = activeEditor();
  if (!editor) return;

  if (!editor.selection.isEmpty) {
    sendSource(editor.document.getText(editor.selection));
    return;
  }

  sendSource(editor.document.getText(currentStatementRange(editor.document, editor.selection.active.line)));
}

function evalBlock() {
  const editor = activeEditor();
  if (!editor) return;

  const range = currentBlockRange(editor.document, editor.selection.active.line);
  sendSource(editor.document.getText(range));
}

function evalFile() {
  const editor = activeEditor();
  if (!editor) return;

  sendSource(editor.document.getText());
}

function currentBlockRange(document, cursorLine) {
  const bounds = currentBlockBounds(documentLines(document), cursorLine);
  return rangeFromLineBounds(document, bounds);
}

function currentStatementRange(document, cursorLine) {
  const bounds = currentStatementBounds(documentLines(document), cursorLine);
  return rangeFromLineBounds(document, bounds);
}

function documentLines(document) {
  const lines = [];
  for (let line = 0; line < document.lineCount; line += 1) {
    lines.push(document.lineAt(line).text);
  }
  return lines;
}

function rangeFromLineBounds(document, bounds) {
  return new vscode.Range(
    new vscode.Position(bounds.start, 0),
    document.lineAt(bounds.end).range.end,
  );
}

function currentBlockBounds(lines, cursorLine) {
  let start = cursorLine;
  let end = cursorLine;

  while (start > 0 && isBlank(lines[start])) start -= 1;
  while (end < lines.length - 1 && isBlank(lines[end])) end += 1;

  while (start > 0 && !isBlank(lines[start - 1])) start -= 1;
  while (end < lines.length - 1 && !isBlank(lines[end + 1])) end += 1;

  let expanded = expandBoundsToStatements(lines, { start, end });
  while (expanded.start !== start || expanded.end !== end) {
    start = expanded.start;
    end = expanded.end;
    expanded = expandBoundsToStatements(lines, { start, end });
  }
  return expanded;
}

function currentStatementBounds(lines, cursorLine) {
  if (lines.length === 0) return { start: 0, end: 0 };
  if (isBlank(lines[cursorLine])) return { start: cursorLine, end: cursorLine };

  const statements = statementBounds(lines);
  return statements.find((statement) => cursorLine >= statement.start && cursorLine <= statement.end)
    || { start: cursorLine, end: cursorLine };
}

function expandBoundsToStatements(lines, bounds) {
  if (lines.length === 0) return { start: 0, end: 0 };
  const statements = statementBounds(lines);
  let start = bounds.start;
  let end = bounds.end;
  for (const statement of statements) {
    if (statement.end < bounds.start || statement.start > bounds.end) continue;
    start = Math.min(start, statement.start);
    end = Math.max(end, statement.end);
  }
  return { start, end };
}

function statementBounds(lines) {
  const statements = [];
  const depth = { paren: 0, bracket: 0, brace: 0 };
  let start;

  for (let line = 0; line < lines.length; line += 1) {
    const text = lines[line];
    if (start === undefined && isBlank(text)) continue;
    if (start === undefined) start = line;

    updateDepth(text, depth);

    if (isDepthZero(depth)) {
      statements.push({ start, end: line });
      start = undefined;
    }
  }

  if (start !== undefined) statements.push({ start, end: lines.length - 1 });
  return statements;
}

function updateDepth(text, depth) {
  const line = stripLineComment(text);
  for (let index = 0; index < line.length; index += 1) {
    const ch = line[index];
    if (ch === '"') index = skipString(line, index);
    else if (ch === "(") depth.paren += 1;
    else if (ch === "[") depth.bracket += 1;
    else if (ch === "{") depth.brace += 1;
    else if (ch === ")" && depth.paren > 0) depth.paren -= 1;
    else if (ch === "]" && depth.bracket > 0) depth.bracket -= 1;
    else if (ch === "}" && depth.brace > 0) depth.brace -= 1;
  }
}

function skipString(text, quoteIndex) {
  let index = quoteIndex + 1;
  while (index < text.length && text[index] !== '"') index += 1;
  return index;
}

function isCommentStart(text, index) {
  return text[index] === "/" && (index === 0 || /\s/.test(text[index - 1]));
}

function stripLineComment(text) {
  for (let index = 0; index < text.length; index += 1) {
    if (isCommentStart(text, index)) return text.slice(0, index).trimEnd();
  }
  return text;
}

function updateDelimiterStack(text, stack) {
  for (let index = 0; index < text.length; index += 1) {
    const ch = text[index];
    if (ch === '"') {
      index = skipString(text, index);
      continue;
    }
    if (ch === "(" || ch === "[" || ch === "{") {
      stack.push(ch);
    } else if (ch === ")" || ch === "]" || ch === "}") {
      const expected = ch === ")" ? "(" : ch === "]" ? "[" : "{";
      if (stack[stack.length - 1] === expected) stack.pop();
    }
  }
}

function isDepthZero(depth) {
  return depth.paren === 0 && depth.bracket === 0 && depth.brace === 0;
}

function isBlank(text) {
  return text.trim().length === 0;
}

function sendSource(source) {
  const text = source.replace(/\r\n?/g, "\n");
  if (text.trim().length === 0) return;

  const lines = sourceToReplLines(text);
  if (lines.length === 0) return;

  const repl = ensureTerminal();
  for (const line of lines) {
    repl.sendText(line, true);
  }
}

function sourceToReplLines(source) {
  const lines = source.split("\n");
  const output = [];
  for (const bounds of statementBounds(lines)) {
    const collapsed = collapseStatementLines(lines.slice(bounds.start, bounds.end + 1));
    if (collapsed.length > 0) output.push(collapsed);
  }
  return output;
}

function collapseStatementLines(lines) {
  let output = "";
  let pendingSeparator = "";
  const stack = [];

  for (const raw of lines) {
    const line = stripLineComment(raw).trim();
    if (line.length === 0) continue;
    if (output.length > 0) output += startsWithClosingDelimiter(line) ? " " : pendingSeparator || " ";
    output += line;
    updateDelimiterStack(line, stack);
    pendingSeparator = continuationSeparator(line, stack);
  }

  return output;
}

function continuationSeparator(line, stack) {
  if (endsWithOpeningDelimiter(line)) return " ";
  const top = stack.length > 0 ? stack[stack.length - 1] : undefined;
  if (top === "[") return " ";
  return ";";
}

function endsWithOpeningDelimiter(line) {
  const trimmed = line.trimEnd();
  return trimmed.endsWith("(") || trimmed.endsWith("[") || trimmed.endsWith("{");
}

function startsWithClosingDelimiter(line) {
  const trimmed = line.trimStart();
  return trimmed.startsWith(")") || trimmed.startsWith("]") || trimmed.startsWith("}");
}

function configuredWorkingDirectory() {
  const configured = config().get("workingDirectory", "");
  if (configured) return configured;
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  return folder ? folder.uri.fsPath : undefined;
}

function configuredEnvironment(binaryPath) {
  const configured = config().get("environment", {});
  const env = {};
  for (const [key, value] of Object.entries(configured)) {
    if (typeof value === "string") env[key] = value;
  }
  return withInferredMlxLibraryPath(binaryPath, env);
}

function withInferredMlxLibraryPath(binaryPath, env) {
  if (process.platform !== "darwin" || env.DYLD_LIBRARY_PATH) return env;
  if (!path.isAbsolute(binaryPath)) return env;

  const workspaceRoot = path.resolve(path.dirname(binaryPath), "..", "..", "..", "..");
  const candidates = [
    path.join(workspaceRoot, ".artifacts", "mlx", "macos-default-install", "lib"),
    path.join(workspaceRoot, ".artifacts", "mlx", "macos-kiwi-install", "lib"),
    path.join(workspaceRoot, ".artifacts", "mlx", "macos-cpuonly-install", "lib"),
  ];
  const mlxLib = candidates.find((candidate) => fs.existsSync(path.join(candidate, "libmlx.dylib")));
  if (mlxLib) env.DYLD_LIBRARY_PATH = mlxLib;
  return env;
}

module.exports = {
  activate,
  deactivate,
  _test: {
    currentBlockBounds,
    currentStatementBounds,
    sourceToReplLines,
    statementBounds,
    stripLineComment,
    collapseStatementLines,
  },
};
