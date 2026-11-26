import { MAX_PATH_BYTES, MemoryFS } from "./vfs.js";

const encoder = new TextEncoder();
const nameDecoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const EMPTY = new Uint8Array(0);
const RANDOM_CHUNK_BYTES = 65536;

function joinBytes(chunks, length) {
  if (chunks.length === 1) return chunks[0];
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

function mixSeed(seed) {
  const u64 = (value) => BigInt.asUintN(64, value);
  let x = u64(seed + 0x9e3779b97f4a7c15n);
  x = u64((x ^ (x >> 30n)) * 0xbf58476d1ce4e5b9n);
  x = u64((x ^ (x >> 27n)) * 0x94d049bb133111ebn);
  return x ^ (x >> 31n);
}

export function createOsImports(mem, options = {}) {
  const {
    fs = new MemoryFS(options.files ? { files: options.files } : {}),
    args: argv = ["goose.wasm"],
    env = {},
    resourceDir = "/",
    stdin = EMPTY,
    writeStdout,
    writeStderr,
    flushStdout,
    sleepMs,
    maxMainThreadSleepMs = 50,
    nowMs = Date.now,
    monotonicMs = () => performance.now(),
    getRandomValues = (bytes) => globalThis.crypto.getRandomValues(bytes),
  } = options;
  const resources = resourceDir && !resourceDir.endsWith("/") ? resourceDir + "/" : resourceDir;
  let getStdinChunk;
  let input;
  let cursor;
  let lastClockNs = 0n;
  let seedCounter = 0n;
  let sleepWord;

  function resetStdin(value = EMPTY) {
    getStdinChunk = typeof value === "function" ? value : null;
    input = getStdinChunk ? EMPTY : typeof value === "string" ? encoder.encode(value) : value;
    cursor = 0;
  }

  resetStdin(stdin);

  function hasInput() {
    while (cursor === input.length && getStdinChunk) {
      const chunk = getStdinChunk();
      if (chunk === null) {
        getStdinChunk = null;
      } else {
        input = chunk;
        cursor = 0;
      }
    }
    return cursor < input.length;
  }

  function takeInput(out, limit = Infinity) {
    if (!(limit > 0)) return 0;
    const chunks = [];
    let length = 0;
    while (length < limit && hasInput()) {
      const end = Math.min(cursor + limit - length, input.length);
      chunks.push(input.slice(cursor, end));
      length += end - cursor;
      cursor = end;
    }
    if (length) mem.appendBuilder(out, joinBytes(chunks, length));
    return length > 0 ? 1 : 0;
  }

  function pathOperation(method) {
    return (...args) => fs[method](mem.readSlice(args).bytes) ? 1 : 0;
  }

  function twoSlices(method) {
    return (...args) => {
      const first = mem.readSlice(args);
      const second = mem.readSlice(args, first.next);
      return fs[method](first.bytes, second.bytes) ? 1 : 0;
    };
  }

  function streamOutput(write) {
    return (...args) => {
      const slice = mem.readSlice(args);
      if (slice.len > 0) write?.(slice.bytes);
    };
  }

  function wallClock() {
    return BigInt(Math.trunc(nowMs())) * 1000000n;
  }

  function clock() {
    const ns = BigInt(Math.trunc(monotonicMs() * 1e6));
    if (ns > lastClockNs) lastClockNs = ns;
    return lastClockNs;
  }

  function fillRandom(bytes) {
    try {
      getRandomValues(bytes);
    } catch (error) {
      // Some Web Crypto implementations require an unshared backing buffer.
      if (options.getRandomValues || !(error instanceof TypeError)
          || typeof SharedArrayBuffer === "undefined" || !(bytes.buffer instanceof SharedArrayBuffer)) {
        throw error;
      }
      const copy = new Uint8Array(bytes.length);
      getRandomValues(copy);
      bytes.set(copy);
    }
  }

  const imports = {
    gs_trim_memory: () => 1,

    gs_os_read_file(...args) {
      const path = mem.readSlice(args);
      const data = fs.readFile(path.bytes);
      if (data === null) return 0;
      mem.appendBuilder(args[path.next], data);
      return 1;
    },

    gs_os_write_file: twoSlices("writeFile"),
    gs_os_write_file_atomic: twoSlices("writeFileAtomic"),
    gs_os_append_file: twoSlices("appendFile"),
    gs_os_file_exists: pathOperation("fileExists"),
    gs_os_remove_file: pathOperation("removeFile"),
    gs_os_rename_file: twoSlices("renameFile"),
    gs_os_make_dir: pathOperation("makeDir"),
    gs_os_is_dir: pathOperation("isDir"),
    gs_os_remove_dir: pathOperation("removeDir"),

    gs_os_list_dir(...args) {
      const path = mem.readSlice(args);
      const entries = fs.listDir(path.bytes);
      if (entries === null) return 0;
      const data = new Uint8Array(entries.reduce((size, entry) => size + entry.length + 1, 0));
      let offset = 0;
      for (const entry of entries) {
        data.set(entry, offset);
        offset += entry.length;
        data[offset++] = 10;
      }
      mem.appendBuilder(args[path.next], data);
      return 1;
    },

    gs_os_write_stdout: streamOutput(writeStdout),
    gs_os_write_stderr: streamOutput(writeStderr),
    gs_os_flush_stdout() {
      flushStdout?.();
    },

    gs_os_read_line(out) {
      if (!hasInput()) return 0;
      const chunks = [];
      let length = 0;
      let newline = false;
      do {
        const at = input.indexOf(10, cursor);
        newline = at !== -1;
        const end = newline ? at : input.length;
        if (end > cursor) {
          chunks.push(input.slice(cursor, end));
          length += end - cursor;
        }
        cursor = newline ? end + 1 : end;
      } while (!newline && hasInput());

      const line = joinBytes(chunks, length);
      mem.appendBuilder(out, newline && line.at(-1) === 13 ? line.subarray(0, -1) : line);
      return 1;
    },

    gs_os_read_stdin(out) {
      takeInput(out);
    },

    gs_os_read_stdin_max(out, max) {
      return takeInput(out, Math.trunc(Number(max)));
    },

    gs_os_arg_count: () => BigInt(argv.length),
    gs_os_arg(i, out) {
      const index = Number(i);
      if (Number.isInteger(index) && index >= 0 && index < argv.length) {
        mem.appendBuilder(out, argv[index]);
      }
    },

    gs_os_getenv(...args) {
      const name = mem.readSlice(args);
      if (name.bytes.length >= MAX_PATH_BYTES || name.bytes.includes(0)) return 0;
      let key;
      try {
        key = nameDecoder.decode(name.bytes);
      } catch {
        return 0;
      }
      const value = env instanceof Map ? env.get(key) : Object.hasOwn(env, key) ? env[key] : undefined;
      if (value === undefined) return 0;
      mem.appendBuilder(args[name.next], value);
      return 1;
    },

    gs_os_resource_dir(out) {
      if (!resources) return 0;
      mem.appendBuilder(out, resources);
      return 1;
    },

    gs_os_time_ns: wallClock,
    gs_os_clock_ns: clock,

    gs_os_sleep_ms(ms) {
      const delay = Number(ms);
      if (!(delay > 0)) return;
      if (sleepMs) {
        sleepMs(delay);
        return;
      }
      try {
        sleepWord ??= new Int32Array(new SharedArrayBuffer(4));
        Atomics.wait(sleepWord, 0, 0, delay);
      } catch {
        const cap = Number.isFinite(maxMainThreadSleepMs) ? maxMainThreadSleepMs : 50;
        const deadline = performance.now() + Math.min(delay, Math.max(0, cap));
        while (performance.now() < deadline) {}
      }
    },

    gs_os_random_u64() {
      const bytes = new Uint8Array(8);
      try {
        getRandomValues(bytes);
        return new DataView(bytes.buffer).getBigUint64(0, true);
      } catch {
        // The upstream seed API falls back to clock-derived PRNG seeds.
        return mixSeed(mixSeed(wallClock() ^ clock()) ^ ++seedCounter);
      }
    },

    gs_os_random_bytes(...args) {
      const { len, view } = mem.readSliceView(args);
      if (len <= 0) return 1;
      try {
        for (let at = 0; at < len; at += RANDOM_CHUNK_BYTES) {
          fillRandom(view.subarray(at, at + RANDOM_CHUNK_BYTES));
        }
        return 1;
      } catch {
        return 0;
      }
    },
  };

  return { imports, fs, resetStdin };
}
