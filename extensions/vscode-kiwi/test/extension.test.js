"use strict";

const assert = require("assert");
const Module = require("module");

const originalLoad = Module._load;
Module._load = function load(request, parent, isMain) {
  if (request === "vscode") return {};
  return originalLoad.apply(this, arguments);
};

const {
  currentBlockBounds,
  currentStatementBounds,
  sourceToReplLines,
  stripLineComment,
} = require("../src/extension.js")._test;

assert.deepStrictEqual(
  sourceToReplLines("f:{\n x+1\n}\nf 3\n"),
  ["f:{ x+1 }", "f 3"],
);

assert.deepStrictEqual(
  sourceToReplLines("f:{\n / comment with } ] )\n\n x+1 / inline comment with }\n}\nf 3\n"),
  ["f:{ x+1 }", "f 3"],
);

assert.deepStrictEqual(
  sourceToReplLines("x:10 20 30 40\nx[1\n 2]\n"),
  ["x:10 20 30 40", "x[1 2]"],
);

assert.deepStrictEqual(
  sourceToReplLines("x:(1 2 3\n 4 5 6)\nx\n"),
  ["x:(1 2 3;4 5 6)", "x"],
);

assert.deepStrictEqual(sourceToReplLines("+/!9\n"), ["+/!9"]);

assert.deepStrictEqual(
  sourceToReplLines("s:\"{ not a delimiter }\"\ns\n"),
  ["s:\"{ not a delimiter }\"", "s"],
);

assert.strictEqual(stripLineComment("x+1 / inline"), "x+1");
assert.strictEqual(stripLineComment("+/!9"), "+/!9");
assert.strictEqual(stripLineComment("\"a / b\""), "\"a");

{
  const lines = ["normalize:{", " x%+/x", "}", "v:1 2 3", "normalize v"];
  assert.deepStrictEqual(currentStatementBounds(lines, 1), { start: 0, end: 2 });
  assert.deepStrictEqual(currentBlockBounds(lines, 1), { start: 0, end: 4 });
}
