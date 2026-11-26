import { runGoose } from "./index.js";

async function runRequest({ id, wasmBytes, url, options = {} }) {
  try {
    const send = (type) => (chunk) => {
      self.postMessage({ id, type, chunk }, [chunk.buffer]);
    };
    const { sab, ...runOptions } = options;
    const sleepState = sab ? new Int32Array(sab, 0, 1) : null;
    const { fs, returnValue, ...result } = await runGoose(wasmBytes ?? url, {
      ...runOptions,
      sleepMs: sleepState ? (ms) => { Atomics.wait(sleepState, 0, 0, ms); } : undefined,
      onStdout: send("stdout"),
      onStderr: send("stderr"),
    });
    self.postMessage({ id, type: "result", result: { ...result, files: fs.snapshot() } });
  } catch (error) {
    self.postMessage({ id, type: "error", message: error instanceof Error ? error.message : String(error) });
  }
}

const workerEntry = Symbol.for("goose.web.worker");
const isWorker = typeof self !== "undefined" && (
  (typeof WorkerGlobalScope !== "undefined" && self instanceof WorkerGlobalScope) || self[workerEntry] === true
);

if (isWorker) {
  delete self[workerEntry];
  self.addEventListener("message", ({ data }) => {
    if (data?.type === "run") void runRequest(data);
  });
}

async function sourceBytes(source) {
  source = await source;
  if (typeof source === "string" || source instanceof URL) {
    source = await globalThis.fetch(source);
  }
  if (typeof Response !== "undefined" && source instanceof Response) {
    if (!source.ok) throw new Error(`Could not load Wasm (HTTP ${source.status})`);
    return source.arrayBuffer();
  }
  if (ArrayBuffer.isView(source)) {
    return new Uint8Array(source.buffer, source.byteOffset, source.byteLength).slice().buffer;
  }
  if (source instanceof ArrayBuffer) return source.slice(0);
  throw new TypeError("Expected Wasm bytes, a Response, or a URL");
}

export function createGooseWorker(workerOptions = {}) {
  let worker = workerOptions.worker;
  let bootstrapURL;
  if (!worker) {
    if (typeof Worker !== "function") {
      throw new Error("Web Worker is unavailable. Pass a compatible worker in options.worker.");
    }
    const url = new URL("./worker.js", import.meta.url);
    // Some non-browser hosts implement Worker without exposing its scope constructor.
    if (typeof WorkerGlobalScope === "undefined" && typeof self !== "undefined" && !self.document) {
      const script = `self[Symbol.for(${JSON.stringify(Symbol.keyFor(workerEntry))})] = true;
        await import(${JSON.stringify(url.href)});
        self.postMessage({ type: "ready" });`;
      bootstrapURL = URL.createObjectURL(new Blob([script], { type: "text/javascript" }));
    }
    try {
      worker = new Worker(bootstrapURL ?? url, { type: "module" });
    } catch (error) {
      if (bootstrapURL) URL.revokeObjectURL(bootstrapURL);
      throw error;
    }
  }
  const pending = new Map();
  let markReady;
  const ready = bootstrapURL ? new Promise((resolve) => { markReady = resolve; }) : Promise.resolve();
  let nextId = 0;
  let failure;

  function onMessage({ data }) {
    if (data?.type === "ready") {
      markReady?.();
      return;
    }
    const request = pending.get(data?.id);
    if (!request) return;
    const { id, type, result, message, chunk } = data;
    try {
      if (type === "stdout" || type === "stderr") {
        const stream = request[type];
        if (stream.callback) stream.callback(chunk, stream.decoder.decode(chunk, { stream: true }));
      } else if (type === "result" || type === "error") {
        pending.delete(id);
        if (type === "result") request.resolve(result);
        else request.reject(new Error(message));
      }
    } catch (error) {
      pending.delete(id);
      request.reject(error);
    }
  }

  function rejectPending(error) {
    failure ??= error;
    for (const { reject } of pending.values()) reject(failure);
    pending.clear();
    markReady?.();
  }

  function onError(event) {
    rejectPending(event.error ?? new Error(event.message || "Goose worker failed"));
  }

  worker.addEventListener("message", onMessage);
  worker.addEventListener("error", onError);
  worker.addEventListener("messageerror", onError);

  return {
    run(source, runOptions = {}) {
      if (failure) return Promise.reject(failure);
      const id = nextId++;
      const { onStdout, onStderr, args, env, files, dirs, cwd, resourceDir, stdin,
        memory64, entry, entryArgs, sab } = runOptions;
      const options = { args, env, files, dirs, cwd, resourceDir, stdin,
        memory64, entry, entryArgs, sab };
      return new Promise((resolve, reject) => {
        pending.set(id, {
          resolve, reject,
          stdout: { callback: onStdout, decoder: new TextDecoder("utf-8", { ignoreBOM: true }) },
          stderr: { callback: onStderr, decoder: new TextDecoder("utf-8", { ignoreBOM: true }) },
        });
        Promise.all([sourceBytes(source), ready]).then(([wasmBytes]) => {
          if (pending.has(id)) worker.postMessage({ id, type: "run", wasmBytes, options }, [wasmBytes]);
        }).catch((error) => {
          if (pending.delete(id)) reject(error);
        });
      });
    },
    terminate() {
      rejectPending(new Error("Goose worker terminated"));
      worker.removeEventListener("message", onMessage);
      worker.removeEventListener("error", onError);
      worker.removeEventListener("messageerror", onError);
      worker.terminate();
      if (bootstrapURL) URL.revokeObjectURL(bootstrapURL);
    },
  };
}
