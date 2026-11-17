// Run multiple compiler invocations on a single eagerly compiled module.
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { once, on } from "node:events";
import { createInterface } from "node:readline";
import { Worker, isMainThread, parentPort, workerData } from "node:worker_threads";
import { runModule } from "../scripts/run_wasm.mjs";

if (isMainThread) {
  const worker = new Worker(new URL(import.meta.url), {
    workerData: process.argv[2],
    resourceLimits: { stackSizeMb: 256 },
  });
  try {
    const [ready] = await once(worker, "message");
    console.log(JSON.stringify(ready));
    const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
    for await (const line of lines) {
      const response = once(worker, "message");
      worker.postMessage(JSON.parse(line));
      const [result] = await response;
      console.log(JSON.stringify(result));
    }
  } finally {
    await worker.terminate();
  }
} else {
  const bytes = readFileSync(workerData);
  const started = process.hrtime.bigint();
  const module = new WebAssembly.Module(bytes);
  const compiledAt = process.hrtime.bigint();
  parentPort.postMessage({
    source_sha256: createHash("sha256").update(bytes).digest("hex"),
    // Capture only the eager compilation time.
    module_compile_ns: Number(compiledAt - started),
    node: process.version,
    v8: process.versions.v8,
    exec_argv: process.execArgv,
  });
  for await (const [argv] of on(parentPort, "message")) {
    const result = await runModule(module, Buffer.alloc(0), [workerData, ...argv]);
    parentPort.postMessage({ ...result, stdout: result.stdout.toString("base64") });
  }
}
