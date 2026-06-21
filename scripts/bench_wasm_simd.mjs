#!/usr/bin/env node
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(SCRIPT_DIR, "..");

const DEFAULT_CASES = [
  {
    name: "int_array_add",
    setup: "a:100000#3 1 4 1 5 9 2 6\nb:100000#2 7 1 8 2 8 1 8",
    command: "\\t:200 a+b",
  },
  {
    name: "int_scalar_add",
    setup: "a:100000#3 1 4 1 5 9 2 6",
    command: "\\t:400 a+7",
  },
  {
    name: "int_array_mul",
    setup: "a:100000#3 1 4 1 5 9 2 6\nb:100000#2 7 1 8 2 8 1 8",
    command: "\\t:100 a*b",
  },
  {
    name: "int_scalar_mul",
    setup: "a:100000#3 1 4 1 5 9 2 6",
    command: "\\t:200 a*7",
  },
  {
    name: "int16_array_mul",
    setup: "a:100000#130 140 150 160 170 180 190 200\nb:100000#140 130 120 110 100 90 80 70",
    command: "\\t:140 a*b",
  },
  {
    name: "int32_array_mul",
    setup: "a:100000#40000 42000 41000 43000\nb:100000#45000 44000 43000 42000",
    command: "\\t:120 a*b",
  },
  {
    name: "float_array_add",
    setup: "a:(100000#3 1 4 1 5 9 2 6)*1.0\nb:(100000#2 7 1 8 2 8 1 8)*1.0",
    command: "\\t:200 a+b",
  },
  {
    name: "float_array_div",
    setup: "a:(100000#3 1 4 1 5 9 2 6)*1.0\nb:a+2.0\nc:a+1.0",
    command: "\\t:100 b%c",
  },
  {
    name: "bool_and",
    setup: "a:100000#10101010b\nb:100000#11001100b",
    command: "\\t:1000 a&b",
  },
  {
    name: "int_equal",
    setup: "a:100000#3 1 4 1 5 9 2 6\nb:100000#3 1 4 1 5 9 2 0",
    command: "\\t:200 a=b",
  },
  {
    name: "int_less",
    setup: "a:100000#3 1 4 1 5 9 2 6\nb:100000#2 7 1 8 2 8 1 8",
    command: "\\t:200 a<b",
  },
  {
    name: "int16_less",
    setup: "a:100000#300 100 400 100 500 900 200 600\nb:100000#200 700 100 800 200 800 100 800",
    command: "\\t:120 a<b",
  },
  {
    name: "int32_less",
    setup: "a:100000#300000 100000 400000 100000 500000 900000 200000 600000\nb:100000#200000 700000 100000 800000 200000 800000 100000 800000",
    command: "\\t:80 a<b",
  },
  {
    name: "mixed_int_less",
    setup: "a:100000#3 1 4 1 5 9 2 6\nb:100000#300 100 400 100 500 900 200 0",
    command: "\\t:80 a<b",
  },
  {
    name: "int_scalar_equal",
    setup: "a:100000#3 1 4 1 5 9 2 6",
    command: "\\t:200 a=1",
  },
  {
    name: "float_equal",
    setup: "a:(100000#3 1 4 1 5 9 2 6)*1.0\nb:(100000#3 1 4 1 5 9 2 0)*1.0",
    command: "\\t:100 a=b",
  },
  {
    name: "int_float_less",
    setup: "a:100000#3 1 4 1 5 9 2 6\nb:(100000#3 2 4 0 6 9 3 7)*1.0",
    command: "\\t:100 a<b",
  },
  {
    name: "where_i16_half",
    setup: "m:32000#10101010b",
    command: "\\t:300 &m",
  },
  {
    name: "where_i32_half",
    setup: "m:100000#10101010b",
    command: "\\t:120 &m",
  },
  {
    name: "where_i32_sparse",
    setup: "m:100000#10000000b",
    command: "\\t:160 &m",
  },
  {
    name: "compare_where_i32",
    setup: "a:100000#3 1 4 1 5 9 2 6\nb:100000#2 7 1 8 2 8 1 8",
    command: "\\t:80 &(a<b)",
  },
  {
    name: "mask_index_i32_half",
    setup: "x:100000#300000 100000 400000 100000 500000 900000 200000 600000\nm:(100000#0 1 0 1)=1",
    command: "\\t:100 x@m",
  },
  {
    name: "where_index_i32_half",
    setup: "x:100000#300000 100000 400000 100000 500000 900000 200000 600000\nm:(100000#0 1 0 1)=1",
    command: "\\t:80 x@&m",
  },
  {
    name: "filter_i32_compare",
    setup: "x:100000#300000 100000 400000 100000 500000 900000 200000 600000",
    command: "\\t:80 {x<500000}#x",
  },
  {
    name: "mask_index_f64_half",
    setup: "x:(100000#3 1 4 1 5 9 2 6)*1.0\nm:(100000#0 1 0 1)=1",
    command: "\\t:80 x@m",
  },
  {
    name: "filter_f64_compare",
    setup: "x:(100000#3 1 4 1 5 9 2 6)*1.0",
    command: "\\t:60 {x<5.0}#x",
  },
  {
    name: "string_mask_half",
    setup: "s:100000#\"abcdefgh\"\nm:100000#10101010b",
    command: "\\t:120 {m}#s",
  },
  {
    name: "string_mask_sparse",
    setup: "s:100000#\"abcdefgh\"\nm:100000#10000000b",
    command: "\\t:160 {m}#s",
  },
  {
    name: "string_mask_dense",
    setup: "s:100000#\"abcdefgh\"\nm:100000#11111110b",
    command: "\\t:80 {m}#s",
  },
  {
    name: "string_find_table_miss",
    setup: "s:100000#\"aaaaaaaa\"\nq:\"bcdefghijklmnopq\"",
    command: "\\t:250 s?q",
  },
  {
    name: "string_find_table_dense_hit",
    setup: "s:100000#\"abcdefghijklmnopqrstuvwxyz012345\"\nq:\"bcdefghijklmnopq\"",
    command: "\\t:400 s?q",
  },
  {
    name: "string_equal_scalar",
    setup: "s:100000#\"abcdefgh\"",
    command: "\\t:300 s=\"a\"",
  },
  {
    name: "string_equal_array",
    setup: "s:100000#\"abcdefgh\"\nt:100000#\"abcdxfgh\"",
    command: "\\t:250 s=t",
  },
  {
    name: "scan_add_i8_to_i32",
    setup: "x:100000#3 1 4 1 5 9 2 6",
    command: "\\t:220 +\\x",
  },
  {
    name: "scan_add_i16_to_i32",
    setup: "x:100000#300 100 400 100 500 900 200 600",
    command: "\\t:180 +\\x",
  },
  {
    name: "scan_add_i32_to_i64",
    setup: "x:100000#300000 100000 400000 100000 500000 900000 200000 600000",
    command: "\\t:120 +\\x",
  },
  {
    name: "scan_add_bit",
    setup: "x:100000#10101010b",
    command: "\\t:220 +\\x",
  },
  {
    name: "scan_add_f64",
    setup: "x:(100000#3 1 4 1 5 9 2 6)*1.0",
    command: "\\t:160 +\\x",
  },
  {
    name: "scan_min_i32_unsorted",
    setup: "x:100000#300000 100000 400000 100000 500000 900000 200000 600000",
    command: "\\t:160 &\\x",
  },
  {
    name: "scan_max_i32_unsorted",
    setup: "x:100000#300000 100000 400000 100000 500000 900000 200000 600000",
    command: "\\t:160 |\\x",
  },
  {
    name: "transpose_i8_tall",
    setup: "x:256 32#1 2 3 4 5 6 7 8",
    command: "\\t:120 (+x)+1",
  },
  {
    name: "transpose_i16_tall",
    setup: "x:256 32#(1*!8192)",
    command: "\\t:120 (+x)+1",
  },
  {
    name: "transpose_i16_wide",
    setup: "x:32 256#(1*!8192)",
    command: "\\t:120 (+x)+1",
  },
  {
    name: "transpose_i32_square",
    setup: "x:128 128#(300000+!16384)",
    command: "\\t:80 (+x)+1",
  },
  {
    name: "transpose_i64_square",
    setup: "x:128 128#(10000000000+!16384)",
    command: "\\t:60 (+x)+1",
  },
  {
    name: "transpose_f32_square",
    setup: "x:128 128#((1.0e*!16384)%1000.0e)",
    command: "\\t:80 (+x)+1.0e",
  },
  {
    name: "transpose_f64_square",
    setup: "x:128 128#((1.0*!16384)%1000.0)",
    command: "\\t:60 (+x)+1.0",
  },
  {
    name: "sum_i8",
    setup: "x:100000#3 1 4 1 5 9 2 6",
    command: "\\t:1000 +/x",
  },
  {
    name: "sum_i16",
    setup: "x:100000#300 100 400 100 500 900 200 600",
    command: "\\t:1000 +/x",
  },
  {
    name: "sum_i32",
    setup: "x:100000#300000 100000 400000 100000 500000 900000 200000 600000",
    command: "\\t:800 +/x",
  },
  {
    name: "sum_i64",
    setup: "x:100000#3000000000 -3000000000 2000000000 -2000000000",
    command: "\\t:600 +/x",
  },
  {
    name: "sum_f64",
    setup: "x:(100000#3 1 4 1 5 9 2 6)*1.0",
    command: "\\t:600 +/x",
  },
  {
    name: "find_i8_miss",
    setup: "a:100000#3 0",
    command: "\\t:1000 a?1",
  },
  {
    name: "find_i16_miss",
    setup: "a:100000#300 100",
    command: "\\t:1000 a?200",
  },
  {
    name: "find_i32_miss",
    setup: "a:100000#300000 100000",
    command: "\\t:800 a?200000",
  },
  {
    name: "find_i64_miss",
    setup: "a:100000#3000000000 -3000000000",
    command: "\\t:600 a?2000000000",
  },
  {
    name: "find_f64_miss",
    setup: "a:(100000#3 0)*1.0",
    command: "\\t:600 a?1.0",
  },
  {
    name: "float_dot",
    setup: "a:(8192#3 1 4 1 5 9 2 6)*1.0\nb:(8192#2 7 1 8 2 8 1 8)*1.0",
    command: "\\t:500 +/a*b",
  },
];

function usage() {
  console.error(`usage: node scripts/bench_wasm_simd.mjs [options]

Compare baseline and simd128 wasm modules with Kiwi \\t-style timing commands.

options:
  --samples N       measured samples per case/variant (default: 7)
  --warmups N       warmup runs before each measured sample (default: 2)
  --baseline PATH   baseline wasm path
  --simd PATH       simd wasm path
  --cases PATH      JSON case file: [{"name","setup","command"}]
  --json            emit JSON instead of TSV
  -h, --help        show this help
`);
}

function parseArgs(argv) {
  const options = {
    samples: 7,
    warmups: 2,
    baseline: resolve(ROOT, "web/kiwi_wasm_module_host_min.wasm"),
    simd: resolve(ROOT, "web/kiwi_wasm_module_host_min_simd.wasm"),
    cases: null,
    json: false,
  };

  for (let idx = 0; idx < argv.length; idx += 1) {
    const arg = argv[idx];
    switch (arg) {
      case "--samples":
        options.samples = parsePositiveInt(argv[++idx], "--samples");
        break;
      case "--warmups":
        options.warmups = parseNonNegativeInt(argv[++idx], "--warmups");
        break;
      case "--baseline":
        options.baseline = resolve(argv[++idx]);
        break;
      case "--simd":
        options.simd = resolve(argv[++idx]);
        break;
      case "--cases":
        options.cases = resolve(argv[++idx]);
        break;
      case "--json":
        options.json = true;
        break;
      case "-h":
      case "--help":
        usage();
        process.exit(0);
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }

  return options;
}

function parsePositiveInt(raw, flag) {
  const value = Number.parseInt(raw, 10);
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${flag} requires a positive integer`);
  }
  return value;
}

function parseNonNegativeInt(raw, flag) {
  const value = Number.parseInt(raw, 10);
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`${flag} requires a non-negative integer`);
  }
  return value;
}

function parseTimingCommand(command) {
  const line = command.trim();
  if (!line.startsWith("\\t")) {
    throw new Error(`timing command must start with \\t: ${command}`);
  }

  let rest = line.slice(2);
  let loops = 1;
  if (rest.startsWith(":")) {
    rest = rest.slice(1);
    const match = rest.match(/^[0-9]+/);
    if (!match) throw new Error(`missing loop count in timing command: ${command}`);
    loops = parsePositiveInt(match[0], "\\t loop count");
    rest = rest.slice(match[0].length);
  }

  const expr = rest.trimStart();
  if (expr.length === 0) {
    throw new Error(`missing expression in timing command: ${command}`);
  }
  return { loops, expr };
}

async function loadCases(casePath) {
  if (!casePath) return DEFAULT_CASES;
  const parsed = JSON.parse(await readFile(casePath, "utf8"));
  if (!Array.isArray(parsed)) throw new Error("--cases JSON must be an array");
  for (const item of parsed) {
    if (!item || typeof item.name !== "string" || typeof item.command !== "string") {
      throw new Error('each case needs string "name" and "command" fields');
    }
    if (item.setup != null && typeof item.setup !== "string") {
      throw new Error(`case ${item.name} has non-string setup`);
    }
  }
  return parsed;
}

function bridgeImports() {
  return {
    bridge: new Proxy(
      {},
      {
        get(_target, prop) {
          if (prop === "then") return undefined;
          return () => 0;
        },
      },
    ),
  };
}

class KiwiWasmRuntime {
  constructor(instance) {
    this.instance = instance;
    this.exports = instance.exports;
    this.encoder = new TextEncoder();
    this.decoder = new TextDecoder();
  }

  static async create(module) {
    const instance = await WebAssembly.instantiate(module, bridgeImports());
    const runtime = new KiwiWasmRuntime(instance);
    runtime.check(runtime.exports.kiwi_init(1));
    return runtime;
  }

  deinit() {
    this.exports.kiwi_deinit();
  }

  writeString(text) {
    const bytes = this.encoder.encode(text);
    this.exports.kiwi_reset_input_arena();
    const ptr = this.exports.kiwi_alloc_bytes(bytes.length, 1);
    if (ptr === 0 && bytes.length !== 0) throw new Error("kiwi_alloc_bytes failed");
    new Uint8Array(this.exports.memory.buffer, ptr, bytes.length).set(bytes);
    return { ptr, len: bytes.length };
  }

  readString(ptr, len) {
    return this.decoder.decode(new Uint8Array(this.exports.memory.buffer, ptr, len));
  }

  lastError() {
    return this.readString(this.exports.kiwi_last_error_ptr(), this.exports.kiwi_last_error_len());
  }

  check(status) {
    if (status !== 0) {
      const error = this.lastError();
      throw new Error(error || `Kiwi wasm call failed with status ${status}`);
    }
  }

  eval(source) {
    if (!source || source.trim().length === 0) return;
    const input = this.writeString(source);
    this.check(this.exports.kiwi_eval(input.ptr, input.len));
  }

  prepare(expr) {
    const input = this.writeString(expr);
    this.check(this.exports.kiwi_bench_prepare(input.ptr, input.len));
  }

  run(loops) {
    const started = performance.now();
    this.check(this.exports.kiwi_bench_run(loops));
    return performance.now() - started;
  }
}

async function measureSample(module, benchCase, warmups) {
  const timing = parseTimingCommand(benchCase.command);
  const runtime = await KiwiWasmRuntime.create(module);
  try {
    runtime.eval(benchCase.setup || "");
    runtime.prepare(timing.expr);
    for (let idx = 0; idx < warmups; idx += 1) {
      runtime.run(timing.loops);
    }
    return runtime.run(timing.loops);
  } finally {
    runtime.deinit();
  }
}

function stats(samples) {
  const sorted = [...samples].sort((a, b) => a - b);
  const sum = samples.reduce((acc, value) => acc + value, 0);
  return {
    min: sorted[0],
    median: sorted[Math.floor(sorted.length / 2)],
    mean: sum / samples.length,
    max: sorted[sorted.length - 1],
    samples,
  };
}

async function measureCase(modules, benchCase, options) {
  const baseline = [];
  const simd = [];
  for (let sample = 0; sample < options.samples; sample += 1) {
    const order = sample % 2 === 0 ? ["baseline", "simd"] : ["simd", "baseline"];
    for (const variant of order) {
      const elapsed = await measureSample(modules[variant], benchCase, options.warmups);
      if (variant === "baseline") baseline.push(elapsed);
      else simd.push(elapsed);
    }
  }

  const timing = parseTimingCommand(benchCase.command);
  const baselineStats = stats(baseline);
  const simdStats = stats(simd);
  return {
    name: benchCase.name,
    command: benchCase.command,
    loops: timing.loops,
    baseline: baselineStats,
    simd: simdStats,
    speedup: baselineStats.median / simdStats.median,
  };
}

function formatNumber(value, digits = 3) {
  return Number.isFinite(value) ? value.toFixed(digits) : "nan";
}

function printTsv(results) {
  console.log([
    "case",
    "loops",
    "baseline_ms",
    "simd_ms",
    "baseline_us_per_loop",
    "simd_us_per_loop",
    "speedup",
    "command",
  ].join("\t"));
  for (const result of results) {
    console.log([
      result.name,
      result.loops,
      formatNumber(result.baseline.median),
      formatNumber(result.simd.median),
      formatNumber((result.baseline.median * 1000) / result.loops),
      formatNumber((result.simd.median * 1000) / result.loops),
      formatNumber(result.speedup, 2),
      result.command,
    ].join("\t"));
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!existsSync(options.baseline)) throw new Error(`missing baseline wasm: ${options.baseline}`);
  if (!existsSync(options.simd)) throw new Error(`missing SIMD wasm: ${options.simd}`);

  const cases = await loadCases(options.cases);
  const modules = {
    baseline: await WebAssembly.compile(await readFile(options.baseline)),
    simd: await WebAssembly.compile(await readFile(options.simd)),
  };

  const results = [];
  for (const benchCase of cases) {
    results.push(await measureCase(modules, benchCase, options));
  }

  if (options.json) {
    console.log(JSON.stringify({ options, results }, null, 2));
  } else {
    printTsv(results);
  }
}

main().catch((error) => {
  console.error(`!${error.message || String(error)}`);
  process.exit(1);
});
