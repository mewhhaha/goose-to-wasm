#!/usr/bin/env node
// Minimal Node/V8 host for the direct compiler's documented scalar ABI.
import { readFileSync, writeFileSync, appendFileSync, statSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { Worker, isMainThread, parentPort, workerData } from "node:worker_threads";
import v8 from "node:v8";

// 64-bit memories (--wasm-memory64 modules, and the C oracle's standalone
// profile) are behind a flag before V8 13.3. It has to be set before the
// first module is compiled, on every thread that compiles one.
{
  const [major, minor] = process.versions.v8.split(".").map(Number);
  if (major < 13 || (major === 13 && minor < 3)) v8.setFlagsFromString("--experimental-wasm-memory64");
}

// A program that recurses deeply (the compiler compiled to Wasm does, over
// its syntax trees) needs more stack than V8 gives the main thread: a module
// given program arguments runs on a worker with this much.
const STACK_MB = 256;

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

// `input` is stdin: bytes as given, or a string as its UTF-8 bytes. fd_read
// sees exactly those bytes. Scalar imports read tokens from a byte-for-byte
// latin1 view, split on ASCII whitespace as the C++ host splits them.
// `programArguments` are what the program's os.arg sees, the program first.
export async function runModule(bytes, input = "", programArguments = ["program"]) {
  const stdin = Buffer.from(input);
  const tokens = stdin.toString("latin1").split(/[ \t\n\r\f\v]+/).filter(Boolean);
  let cursor = 0;
  let instance;
  let sink = 0n;
  const chunks = [];
  const errors = [];
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
  // A slice argument. A 32-bit module passes one i64 of pointer (low 32 bits)
  // and element count; a 64-bit one passes the pointer and the count as two
  // i64, since its slice, a v128, cannot cross to the host. `sliced` gives an
  // import the same arguments either way: `kinds` has an "s" for each slice
  // parameter, which arrives as its bytes, and another letter for each other.
  const sliced = (kinds, action) => (...values) => {
    const wide = values.length > kinds.length;
    const converted = [];
    let at = 0;
    for (const kind of kinds) {
      if (kind !== "s") converted.push(values[at++]);
      else if (wide) { converted.push(memoryBytes(values[at], values[at + 1])); at += 2; }
      else {
        const packed = BigInt.asUintN(64, values[at++]);
        converted.push(memoryBytes(Number(packed & 0xffffffffn), Number(packed >> 32n)));
      }
    }
    return action(...converted);
  };
  // Appends to the growable byte array whose control is at `control` (words
  // base, length, limit, ...; u32 in a 32-bit module, u64 in a 64-bit one):
  // the bytes go at its region's cursor, which is kept in the module's cursor
  // table and moves with them. The module exports the words that find it
  // (docs/TARGET.md), as i64 globals when its memory is 64-bit.
  const appendBytes = (control, data) => {
    const exported = (name) => {
      const global = instance.exports[name];
      if (!(global instanceof WebAssembly.Global)) throw new Error("module does not export " + name);
      return global.value;
    };
    const wide = typeof exported("goose.region_base") === "bigint";
    const bytes = wide ? 8 : 4;
    const word = (name) => wide ? address(exported(name)) : exported(name) >>> 0;
    const read = (at) => {
      const view = memoryView(at, bytes);
      const data = new DataView(view.buffer, view.byteOffset, bytes);
      return wide ? address(data.getBigUint64(0, true)) : data.getUint32(0, true);
    };
    const write = (at, value) => {
      const view = memoryView(at, bytes);
      const data = new DataView(view.buffer, view.byteOffset, bytes);
      if (wide) data.setBigUint64(0, BigInt(value), true); else data.setUint32(0, value, true);
    };
    const header = address(control);
    const length = read(header + bytes), limit = read(header + 2 * bytes);
    const slot = word("goose.region_cursors") + bytes * (Math.floor((limit - word("goose.region_base")) / word("goose.region_bytes")) - 1);
    const cursor = read(slot);
    if (data.length > limit - cursor) throw new Error("goose runtime error: data region exhausted");
    const end = cursor + data.length;
    const memory = instance.exports.memory;
    if (end > memory.buffer.byteLength) {
      const pages = Math.ceil((end - memory.buffer.byteLength) / 65536);
      // A 64-bit memory takes its page count as a BigInt in engines that
      // follow the final interface, as a number in earlier ones.
      try { memory.grow(pages); } catch (failure) { if (!wide || !(failure instanceof TypeError)) throw failure; memory.grow(BigInt(pages)); }
    }
    memoryView(cursor, data.length).set(data);
    write(header + bytes, length + data.length);
    write(slot, end);
  };
  const tried = (action) => { try { return action() ? 1 : 0; } catch { return 0; } };
  const byteSet = (pointer) => memoryView(pointer, 256);
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
      // The stdlib's `os` externs, for a program that reads and writes files
      // (the compiler itself among them). Text goes out through the same
      // buffers as print.
      gs_os_read_file: sliced("sr", (path, control) => tried(() => { appendBytes(control, readFileSync(path.toString("utf8"))); return true; })),
      gs_os_write_file: sliced("ss", (path, data) => tried(() => { writeFileSync(path.toString("utf8"), data); return true; })),
      gs_os_append_file: sliced("ss", (path, data) => tried(() => { appendFileSync(path.toString("utf8"), data); return true; })),
      gs_os_file_exists: sliced("s", (path) => tried(() => statSync(path.toString("utf8")).isFile())),
      gs_os_is_dir: sliced("s", (path) => tried(() => statSync(path.toString("utf8")).isDirectory())),
      gs_os_write_stdout: sliced("s", (text) => { chunks.push(text); }),
      gs_os_write_stderr: sliced("s", (text) => { errors.push(text); }),
      gs_os_flush_stdout: () => {},
      gs_os_arg_count: () => BigInt(programArguments.length),
      gs_os_arg: (index, control) => {
        const at = Number(BigInt.asIntN(64, index));
        if (at >= 0 && at < programArguments.length) appendBytes(control, Buffer.from(programArguments[at]));
      },
      gs_os_getenv: sliced("sr", (name, control) => {
        const value = process.env[name.toString("utf8")];
        if (value === undefined) return 0;
        appendBytes(control, Buffer.from(value));
        return 1;
      }),
      gs_os_resource_dir: () => 0,
      gs_os_clock_ns: () => process.hrtime.bigint(),
      gs_os_time_ns: () => BigInt(Date.now()) * 1000000n,
      // std's byte-set searches: a set's members are its first 256 bytes.
      gs_find_any: sliced("sr", (data, set) => {
        const members = byteSet(set);
        for (let i = 0; i < data.length; i++) if (members[data[i]]) return BigInt(i);
        return -1n;
      }),
      gs_find_pair: sliced("srrr", (data, first, distance, second) => {
        const a = byteSet(first), b = byteSet(second), d = Number(distance);
        for (let i = 0; i + d < data.length; i++) if (a[data[i]] && b[data[i + d]]) return BigInt(i);
        return -1n;
      }),
      // No process can be started from here: libc's system fails.
      system: () => -1,
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
    process.stdout.write("usage: node scripts/run_wasm.mjs module.wasm [--timing-json path] [-- program arguments]\nInput scalars are read from stdin.\n");
    return;
  }
  const module = args.shift();
  let timingPath;
  let programArguments = [module];
  const separator = args.indexOf("--");
  const hosted = separator >= 0;
  if (hosted) programArguments = [module, ...args.splice(separator).slice(1)];
  if (args.length) {
    if (args.length !== 2 || args[0] !== "--timing-json") throw new Error("unknown runner arguments");
    timingPath = args[1];
  }
  const result = !hosted ? await runModule(readFileSync(module), readFileSync(0)) : await new Promise((resolve, reject) => {
    const worker = new Worker(new URL(import.meta.url), {
      workerData: { module, input: readFileSync(0), programArguments },
      resourceLimits: { stackSizeMb: STACK_MB },
    });
    worker.once("message", resolve);
    worker.once("error", reject);
  });
  result.stdout = Buffer.from(result.stdout);
  process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr.endsWith("\n") ? result.stderr : result.stderr + "\n");
  if (timingPath) writeFileSync(timingPath, JSON.stringify(result.timing, null, 2) + "\n");
  process.exitCode = result.exitCode;
}

if (!isMainThread && workerData && workerData.module) {
  runModule(readFileSync(workerData.module), Buffer.from(workerData.input), workerData.programArguments)
    .then((result) => parentPort.postMessage(result));
} else if (isMainThread && process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => { process.stderr.write(`direct Wasm host: ${error.message}\n`); process.exitCode = 1; });
}
