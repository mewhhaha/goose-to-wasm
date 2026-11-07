#!/usr/bin/env node
// One trusted module compilation, fresh instance and input/output state per request.
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { createInterface } from "node:readline";
import { runModule } from "../scripts/run_wasm.mjs";

const [path, expectedHash] = process.argv.slice(2);
const bytes = readFileSync(path);
const sourceHash = createHash("sha256").update(bytes).digest("hex");
if (sourceHash !== expectedHash) throw new Error("Wasm input fingerprint changed");
const started = process.hrtime.bigint();
const prepared = await WebAssembly.compile(bytes);
const compileNs = Number(process.hrtime.bigint() - started);
console.log(JSON.stringify({ type: "ready", pid: process.pid, source_sha256: sourceHash,
  module_construction_count: 1, initial_module_compile_ns: compileNs, versions: process.versions,
  exec_argv: process.execArgv, node_options: process.env.NODE_OPTIONS || "" }));
const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of lines) {
  const request = JSON.parse(line);
  const started = process.hrtime.bigint();
  const result = await runModule(prepared, request.stdin);
  console.log(JSON.stringify({ type: "result", id: request.id, pid: process.pid,
    stdout: result.stdout.toString("utf8"), stderr: result.stderr, exit_code: result.exitCode,
    wall_ns: Number(process.hrtime.bigint() - started), timing: result.timing,
    module_construction_count: 1, source_sha256: sourceHash }));
}
