import { gooseFloat, gooseFloatDigits } from "./float.js";
import { createMemoryAccess, detectMemory64 } from "./memory.js";
import { createMathImports } from "./math.js";
import { createStdImports } from "./std.js";
import { GooseExitError, GooseAbortError, createGooseImports } from "./runtime.js";
import { MAX_PATH_BYTES, MemoryFS, LocalStorageFS, OPFSAdapter } from "./vfs.js";
import { createOsImports } from "./os.js";
import { MAX_SOUNDS, MAX_VOICES, GooseAudioMixer, createAudioImports } from "./audio.js";

export {
  MemoryFS, LocalStorageFS, OPFSAdapter, MAX_PATH_BYTES,
  GooseExitError, GooseAbortError, GooseAudioMixer, MAX_SOUNDS, MAX_VOICES,
  gooseFloat, gooseFloatDigits, detectMemory64,
};
export { createGooseWorker } from "./worker.js";

function outputStream(capture, callback) {
  const chunks = [];
  let decoder = new TextDecoder("utf-8", { ignoreBOM: true });

  function bytes() {
    const result = new Uint8Array(chunks.reduce((size, chunk) => size + chunk.length, 0));
    let offset = 0;
    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }
    return result;
  }

  return {
    write(chunk) {
      if (capture) chunks.push(new Uint8Array(chunk));
      if (callback) callback(new Uint8Array(chunk), decoder.decode(chunk, { stream: true }));
    },
    bytes,
    text: () => new TextDecoder("utf-8", { ignoreBOM: true }).decode(bytes()),
    reset() {
      chunks.length = 0;
      decoder = new TextDecoder("utf-8", { ignoreBOM: true });
    },
  };
}

export function createGooseHost(options = {}) {
  const fs = options.fs ?? new MemoryFS({ files: options.files, dirs: options.dirs, cwd: options.cwd });
  const stdout = outputStream(options.captureOutput !== false, options.onStdout);
  const stderr = outputStream(options.captureOutput !== false, options.onStderr);
  const state = { memory: null, memory64: Boolean(options.memory64), reserve: null };
  const mem = createMemoryAccess(state);
  const io = { writeStdout: stdout.write, writeStderr: stderr.write };
  const goose = createGooseImports(mem, io);
  const osHost = createOsImports(mem, {
    ...io,
    fs,
    args: options.args ?? ["goose.wasm"],
    env: options.env,
    resourceDir: options.resourceDir === undefined ? "/" : options.resourceDir,
    stdin: options.stdin,
    sleepMs: options.sleepMs,
    maxMainThreadSleepMs: options.maxMainThreadSleepMs,
  });
  const audioHost = createAudioImports(mem, { audioContext: options.audioContext });
  const { goose: extraGoose, env: extraEnv, ...extraNamespaces } = options.imports ?? {};
  const env = {
    ...createMathImports(mem),
    ...createStdImports(mem),
    ...osHost.imports,
    ...audioHost.imports,
    ...extraEnv,
  };

  return {
    imports: { ...extraNamespaces, goose: { ...goose, ...extraGoose }, env },
    fs,
    audio: audioHost.mixer,
    state,
    bind(instance, bindOptions = {}) {
      state.memory = instance.exports.memory ?? null;
      state.reserve = instance.exports["goose.reserve"] ?? null;
      if (bindOptions.memory64 !== undefined) state.memory64 = Boolean(bindOptions.memory64);
    },
    stdoutBytes: stdout.bytes,
    stdoutText: stdout.text,
    stderrBytes: stderr.bytes,
    stderrText: stderr.text,
    resetOutput() {
      stdout.reset();
      stderr.reset();
    },
    resetStdin(input) {
      osHost.resetStdin(input);
    },
    dispose() {
      return audioHost.mixer.close();
    },
  };
}

export async function loadGoose(source, options = {}) {
  source = await source;
  if (typeof source === "string" || source instanceof URL) {
    source = await globalThis.fetch(source);
  }

  let memory64 = options.memory64;
  let streaming = false;
  if (typeof Response !== "undefined" && source instanceof Response) {
    if (!source.ok) throw new Error(`Could not load Wasm (HTTP ${source.status})`);
    streaming = options.streaming !== false && typeof memory64 === "boolean"
      && typeof WebAssembly.instantiateStreaming === "function"
      && source.headers.get("Content-Type") === "application/wasm";
    if (!streaming) source = await source.arrayBuffer();
  }
  if (!streaming && !(source instanceof WebAssembly.Module)) {
    if (ArrayBuffer.isView(source)) {
      source = new Uint8Array(source.buffer, source.byteOffset, source.byteLength);
    } else if (!(source instanceof ArrayBuffer)) {
      throw new TypeError("Expected a WebAssembly.Module, Wasm bytes, a Response, or a URL");
    }
    memory64 ??= detectMemory64(source instanceof Uint8Array ? source : new Uint8Array(source));
  }
  memory64 ??= false;

  const host = createGooseHost({ ...options, memory64 });
  let module;
  let instance;
  try {
    if (streaming) {
      ({ module, instance } = await WebAssembly.instantiateStreaming(source, host.imports));
    } else if (source instanceof WebAssembly.Module) {
      module = source;
      instance = await WebAssembly.instantiate(module, host.imports);
    } else {
      ({ module, instance } = await WebAssembly.instantiate(source, host.imports));
    }
    host.bind(instance, { memory64 });
  } catch (error) {
    await host.dispose();
    throw error;
  }

  function run(entry = "_start", ...args) {
    const callable = instance.exports[entry];
    if (typeof callable !== "function") throw new TypeError(`Wasm export "${entry}" is not a function`);
    const start = performance.now();
    let exitCode = 0;
    let aborted = false;
    let abortReason = null;
    let abortLine = null;
    let returnValue;
    try {
      returnValue = callable(...args);
    } catch (error) {
      if (options.throwOnError) throw error;
      if (error instanceof GooseExitError) {
        exitCode = error.code;
      } else if (error instanceof GooseAbortError) {
        exitCode = 1;
        aborted = true;
        abortReason = error.reason;
        abortLine = error.line;
      } else {
        throw error;
      }
    }
    const durationMs = performance.now() - start;
    const stdoutBytes = host.stdoutBytes();
    const stderrBytes = host.stderrBytes();
    const decoder = new TextDecoder("utf-8", { ignoreBOM: true });
    return {
      exitCode, aborted, abortReason, abortLine, returnValue,
      stdout: decoder.decode(stdoutBytes), stderr: decoder.decode(stderrBytes),
      stdoutBytes, stderrBytes, durationMs,
    };
  }

  return { module, instance, exports: instance.exports, host, memory64, run, dispose: host.dispose };
}

export async function runGoose(source, options = {}) {
  const loaded = await loadGoose(source, options);
  try {
    const result = loaded.run(options.entry ?? "_start", ...(options.entryArgs ?? []));
    return { ...result, fs: loaded.host.fs };
  } finally {
    if (options.keepAlive !== true) await loaded.dispose();
  }
}
