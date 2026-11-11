#!/usr/bin/env node
// Minimal Node/V8 host for the direct compiler's documented scalar ABI.
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

// The shortest scientific text of a positive finite f32, chosen as native
// gs_fmt_f32 chooses it: the fewest significant digits that read back as the
// same f32, of those the nearest to its exact value, and of two as near the
// even one. Exact integers decide each step. toPrecision rounds a decimal tie
// up, and one rounded candidate per length misses shorter text below a power
// of two, where the gap to the next f32 down is half the gap up.
function f32Scientific(magnitude) {
  const view = new DataView(new ArrayBuffer(4));
  view.setFloat32(0, magnitude);
  const bits = view.getUint32(0);
  const biased = bits >>> 23;
  const fraction = bits & 0x7fffff;
  const significand = biased ? fraction | 0x800000 : fraction;
  // The value is quarter * 2^binary; what reads back as it reaches from
  // quarter - below to quarter + 2 in the same unit, ends included when the
  // significand is even, since reading rounds a tie to the even significand.
  const quarter = BigInt(significand) * 4n;
  const binary = (biased || 1) - 152;
  const below = fraction === 0 && biased > 1 ? 1n : 2n;
  const inclusive = significand % 2 === 0;
  // Integers proportional to one unit of the value and one unit of 10^scale.
  const scaled = (scale) => [
    (binary > 0 ? 1n << BigInt(binary) : 1n) * (scale < 0 ? 10n ** BigInt(-scale) : 1n),
    (binary < 0 ? 1n << BigInt(-binary) : 1n) * (scale > 0 ? 10n ** BigInt(scale) : 1n),
  ];
  let exponent = Math.floor(Math.log10(magnitude));
  for (;;) {
    const [valueUnit, decimalUnit] = scaled(exponent);
    const leading = quarter * valueUnit / decimalUnit;
    if (leading >= 10n) exponent++;
    else if (leading < 1n) exponent--;
    else break;
  }
  for (let precision = 1; ; precision++) {
    const [valueUnit, decimalUnit] = scaled(exponent - precision + 1);
    const exact = quarter * valueUnit;
    const low = (quarter - below) * valueUnit;
    const high = (quarter + 2n) * valueUnit;
    const truncated = exact / decimalUnit;
    let best;
    let bestDistance;
    for (const digits of [truncated, truncated + 1n]) {
      const candidate = digits * decimalUnit;
      if (inclusive ? candidate < low || candidate > high : candidate <= low || candidate >= high) continue;
      const distance = candidate > exact ? candidate - exact : exact - candidate;
      if (best === undefined || distance < bestDistance || (distance === bestDistance && digits % 2n === 0n)) {
        best = digits;
        bestDistance = distance;
      }
    }
    if (best !== undefined) {
      // A carry to 10^precision spells one more digit at the next power.
      const text = best.toString();
      const digits = text.replace(/0+$/, "");
      return digits[0] + (digits.length > 1 ? "." + digits.slice(1) : "") + "e" + (exponent + text.length - precision);
    }
  }
}

export function gooseFloat(value, bits = 64) {
  if (bits === 32) value = Math.fround(value);
  if (Number.isNaN(value)) return "nan";
  if (value === Infinity) return "inf";
  if (value === -Infinity) return "-inf";
  const negative = value < 0 || Object.is(value, -0);
  if (value === 0) return negative ? "-0.0" : "0.0";
  const magnitude = Math.abs(value);
  const shortest = bits === 32 ? f32Scientific(magnitude) : magnitude.toString();
  const [mantissa, exponentText = "0"] = shortest.toLowerCase().split("e");
  const point = mantissa.includes(".") ? mantissa.indexOf(".") : mantissa.length;
  let digits = mantissa.replace(".", "");
  let leading = 0;
  while (digits[leading] === "0") leading++;
  const exponent = Number(exponentText) + point - leading - 1;
  digits = digits.slice(leading).replace(/0+$/, "");
  let text;
  if (exponent < -4 || exponent >= Math.max(15, digits.length)) {
    text = digits[0];
    if (digits.length > 1) text += "." + digits.slice(1);
    text += "e" + (exponent < 0 ? "-" : "+") + String(Math.abs(exponent)).padStart(2, "0");
  } else if (exponent < 0) {
    text = "0." + "0".repeat(-exponent - 1) + digits;
  } else if (digits.length <= exponent + 1) {
    text = digits + "0".repeat(exponent + 1 - digits.length) + ".0";
  } else {
    text = digits.slice(0, exponent + 1) + "." + digits.slice(exponent + 1);
  }
  return (negative ? "-" : "") + text;
}

class ProgramExit extends Error {
  constructor(code) {
    super("program exit");
    this.code = code;
  }
}

export async function runModule(bytes, input = "") {
  const tokens = input.trim().split(/\s+/).filter(Boolean);
  let cursor = 0;
  let instance;
  let sink = 0n;
  const chunks = [];
  const errors = [];
  const stdin = Buffer.from(input);
  let stdinPosition = 0;
  const append = (text) => chunks.push(Buffer.from(text));
  const token = () => {
    if (cursor >= tokens.length) throw new Error("host input exhausted");
    return tokens[cursor++];
  };
  const address = (value) => {
    if (typeof value === "number") {
      if (!Number.isSafeInteger(value) || value < -2147483648) throw new Error("invalid host address");
      // Direct i32 pointers arrive signed; WASI64 pointers already converted to
      // Number must retain all their bits, including addresses above 4 GiB.
      return value < 0 ? value >>> 0 : value;
    }
    const unsigned = BigInt.asUintN(64, value);
    if (unsigned > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("host address is too large");
    return Number(unsigned);
  };
  const memoryView = (pointer, length) => {
    if (!instance) throw new Error("host memory is unavailable during module initialization");
    const start = address(pointer);
    const size = address(length);
    const memory = instance.exports.memory;
    if (!(memory instanceof WebAssembly.Memory) || start > memory.buffer.byteLength || size > memory.buffer.byteLength - start) {
      throw new Error("host write is outside exported memory");
    }
    return new Uint8Array(memory.buffer, start, size);
  };
  const memoryBytes = (pointer, length) => Buffer.from(memoryView(pointer, length));
  const formatFloat = (pointer, value, bits) => {
    const text = Buffer.from(gooseFloat(value, bits));
    if (text.length > 32) throw new Error("formatted float exceeds host buffer");
    memoryView(pointer, 32).set(text);
    return text.length;
  };
  const write64 = (pointer, value) => {
    const bytes = memoryView(pointer, 8);
    new DataView(bytes.buffer, bytes.byteOffset, 8).setBigUint64(0, BigInt(value), true);
  };
  const read64 = (pointer) => {
    const bytes = memoryView(pointer, 8);
    return new DataView(bytes.buffer, bytes.byteOffset, 8).getBigUint64(0, true);
  };
  const iovecs = (pointer, count) => {
    const base = address(pointer);
    const length = address(count);
    memoryView(base, length * 16);
    const result = [];
    for (let i = 0; i < length; i++) result.push([read64(base + i * 16), read64(base + i * 16 + 8)]);
    return result;
  };
  const imports = {
    goose: {
      write: (pointer, length) => chunks.push(memoryBytes(pointer, length)),
      print_i64: (value) => append(BigInt.asIntN(64, value).toString()),
      print_u64: (value) => append(BigInt.asUintN(64, value).toString()),
      print_f64: (value) => append(gooseFloat(value, 64)),
      print_f32: (value) => append(gooseFloat(value, 32)),
      format_f64: (pointer, value) => formatFloat(pointer, value, 64),
      format_f32: (pointer, value) => formatFloat(pointer, value, 32),
      print_bool: (value) => append(value ? "true" : "false"),
      newline: () => append("\n"),
      abort: (pointer, length, line) => {
        const message = memoryBytes(pointer, length).toString("utf8");
        throw new Error(`goose runtime error: ${message} (line ${line})`);
      },
      exit: (code) => { throw new ProgramExit(code); },
    },
    env: {
      bench_input: () => {
        const text = token();
        if (!/^[+-]?\d+$/.test(text)) throw new Error("host input is not an i64");
        const value = BigInt(text);
        if (value < -(1n << 63n) || value >= (1n << 63n)) throw new Error("host input exceeds i64");
        return value;
      },
      bench_input_f64: () => {
        const text = token().toLowerCase();
        if (text === "nan") return NaN;
        if (text === "inf" || text === "+inf") return Infinity;
        if (text === "-inf") return -Infinity;
        const value = Number(text);
        if (Number.isNaN(value)) throw new Error("host input is not an f64");
        return value;
      },
      bench_clock: () => process.hrtime.bigint(),
      bench_barrier: (value) => { sink = value; return sink; },
      bench_sink: (value) => { sink = value; },
      emscripten_notify_memory_growth: () => {},
    },
    // Emscripten's standalone LP64 C profile has WASI64 pointers and size_t,
    // including 16-byte iovecs. This is deliberately not Node's WASI32 ABI.
    wasi_snapshot_preview1: {
      args_sizes_get: (argc, size) => { write64(argc, 1); write64(size, 8); return 0; },
      args_get: (argv, buffer) => {
        write64(argv, address(buffer));
        memoryView(buffer, 8).set(Buffer.from("program\0"));
        return 0;
      },
      environ_sizes_get: (count, size) => { write64(count, 0); write64(size, 0); return 0; },
      environ_get: () => 0,
      proc_exit: (code) => { throw new ProgramExit(code); },
      clock_time_get: (clock, _precision, out) => {
        if (clock === 0) write64(out, BigInt(Date.now()) * 1000000n);
        else if (clock === 1) write64(out, process.hrtime.bigint());
        else return 28;
        return 0;
      },
      fd_write: (fd, pointer, count, written) => {
        if (fd !== 1 && fd !== 2) return 8;
        let total = 0;
        for (const [start, length] of iovecs(pointer, count)) {
          const bytes = memoryBytes(start, length);
          (fd === 1 ? chunks : errors).push(bytes);
          total += bytes.length;
        }
        write64(written, total);
        return 0;
      },
      fd_read: (fd, pointer, count, read) => {
        if (fd !== 0) return 8;
        let total = 0;
        for (const [start, length] of iovecs(pointer, count)) {
          const size = Math.min(address(length), stdin.length - stdinPosition);
          memoryView(start, size).set(stdin.subarray(stdinPosition, stdinPosition + size));
          stdinPosition += size;
          total += size;
          if (size < address(length)) break;
        }
        write64(read, total);
        return 0;
      },
      fd_close: (fd) => fd >= 0 && fd <= 2 ? 0 : 8,
      fd_seek: (fd) => fd >= 0 && fd <= 2 ? 70 : 8,
    },
  };
  const started = process.hrtime.bigint();
  let instantiated = started;
  let exitCode = 0;
  let error = "";
  try {
    const result = await WebAssembly.instantiate(bytes, imports);
    if (bytes instanceof WebAssembly.Module) {
      instance = result;
    } else {
      instance = result.instance;
    }
    if (typeof instance.exports.__set_stack_limits === "function") {
      instance.exports.emscripten_stack_init();
      instance.exports.__set_stack_limits(
        instance.exports.emscripten_stack_get_base(), instance.exports.emscripten_stack_get_end(),
      );
    }
    instantiated = process.hrtime.bigint();
    if (typeof instance.exports._start !== "function") throw new Error("module does not export _start");
    instance.exports._start();
  } catch (failure) {
    if (failure instanceof ProgramExit) exitCode = failure.code;
    else {
      exitCode = 1;
      error = failure instanceof Error ? failure.message : String(failure);
    }
  }
  const ended = process.hrtime.bigint();
  return {
    stdout: Buffer.concat(chunks), stderr: Buffer.concat(errors).toString("utf8") + error, exitCode,
    timing: {
      engine: "V8", node: process.version, v8: process.versions.v8,
      compile_instantiate_ns: Number(instantiated - started),
      start_function_ns: Number(ended - instantiated),
      engine_total_ns: Number(ended - started),
    },
  };
}

async function main() {
  const args = process.argv.slice(2);
  if (!args.length || args[0] === "--help") {
    process.stdout.write("usage: node scripts/run_wasm.mjs module.wasm [--timing-json path]\nInput scalars are read from stdin.\n");
    return;
  }
  const module = args.shift();
  let timingPath;
  if (args.length) {
    if (args.length !== 2 || args[0] !== "--timing-json") throw new Error("unknown runner arguments");
    timingPath = args[1];
  }
  const result = await runModule(readFileSync(module), readFileSync(0, "utf8"));
  process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr + "\n");
  if (timingPath) writeFileSync(timingPath, JSON.stringify(result.timing, null, 2) + "\n");
  process.exitCode = result.exitCode;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => { process.stderr.write(`direct Wasm host: ${error.message}\n`); process.exitCode = 1; });
}
