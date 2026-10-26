#!/usr/bin/env python3
"""Execute small feature probes in the configured V8 and Wasmtime engines.

Engine capability is distinct from the Goose constructs the new backend lowers.
This script records facts about the target, not a claim of language coverage.
"""
from __future__ import annotations

import argparse
import base64
import importlib.metadata
import json
from pathlib import Path
import subprocess
import sys


PROBES = {
    "numeric": ("(module (func (export \"probe\") (result i32) i32.const 42))", 42),
    "sign_extension": ("(module (func (export \"probe\") (result i32) "
                       "i32.const 255 i32.extend8_s))", -1),
    "multi_value": ("(module (func (export \"probe\") (result i32 i32) i32.const 7 i32.const 9))", [7, 9]),
    "bulk_memory": ("(module (memory 1) (func (export \"probe\") (result i32) "
                    "i32.const 0 i32.const 42 i32.const 1 memory.fill i32.const 0 i32.load8_u))", 42),
    "simd": ("(module (func (export \"probe\") (result i32) "
             "v128.const i32x4 1 2 3 4 i32x4.extract_lane 2))", 3),
    "tail_call": ("(module (func $f (result i32) i32.const 42) "
                  "(func (export \"probe\") (result i32) return_call $f))", 42),
    "memory64": ("(module (memory i64 1) (func (export \"probe\") (result i32) "
                 "i64.const 0 i32.const 42 i32.store i64.const 0 i32.load))", 42),
    "multi_memory": ("(module (memory 1) (memory 2) "
                     "(func (export \"probe\") (result i32) memory.size 1))", 2),
    "exceptions": ("(module (tag $e (param i32)) (func (export \"probe\") (result i32) "
                   "(block $caught (result i32) (try_table (catch $e $caught) "
                   "(throw $e (i32.const 42))) (i32.const 0))))", 42),
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", default="node")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        import wasmtime
    except ImportError:
        parser.error("install requirements.txt for the pinned Wasmtime bindings")
    config = wasmtime.Config()
    for flag in ("wasm_multi_value", "wasm_bulk_memory", "wasm_simd", "wasm_tail_call",
                 "wasm_memory64", "wasm_multi_memory", "wasm_exceptions"):
        setattr(config, flag, True)
    engine = wasmtime.Engine(config)
    v8_script = """
import fs from 'node:fs';
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const results = {};
for (const [name, encoded] of Object.entries(input)) {
  try {
    const bytes = Buffer.from(encoded, 'base64');
    const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes));
    results[name] = {value: instance.exports.probe()};
  } catch (error) { results[name] = {error: String(error)}; }
}
console.log(JSON.stringify({node: process.versions.node, v8: process.versions.v8, results}));
"""
    encoded = {}
    results = {}
    for name, (wat, expected) in PROBES.items():
        try:
            module_bytes = bytes(wasmtime.wat2wasm(wat))
            encoded[name] = base64.b64encode(module_bytes).decode()
            store = wasmtime.Store(engine)
            instance = wasmtime.Instance(store, wasmtime.Module(engine, module_bytes), [])
            value = instance.exports(store)["probe"](store)
            results[name] = {"expected": expected, "wasmtime": value, "wasmtime_ok": value == expected}
        except Exception as error:
            results[name] = {"expected": expected, "wasmtime_error": str(error), "wasmtime_ok": False}
    process = subprocess.run([args.node, "--input-type=module", "-e", v8_script],
                             input=json.dumps(encoded), text=True, capture_output=True, check=False)
    if process.returncode:
        parser.error(process.stderr)
    v8 = json.loads(process.stdout)
    for name, result in results.items():
        observation = v8["results"].get(name, {"error": "probe could not be assembled"})
        result["v8_ok"] = "value" in observation and observation["value"] == result["expected"]
        result["v8"] = observation
    report = {"schema": "goose-engine-probes-v1", "node": v8["node"], "v8": v8["v8"],
              "wasmtime_python": importlib.metadata.version("wasmtime"), "features": results}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0 if all(r["v8_ok"] and r["wasmtime_ok"] for r in results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
