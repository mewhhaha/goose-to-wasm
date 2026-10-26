#!/usr/bin/env python3
"""Check the bounded float-to-memory host ABI on V8 and Wasmtime."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import wasmtime

ROOT = Path(__file__).resolve().parents[1]


def module(bits, value, pointer, capacity, expected=None):
    # Sentinels immediately surround a successful output. A terminating NUL,
    # truncation, or wrong returned length becomes a visible failure.
    payload = "L" + "x" * len(expected) + "R" if expected is not None else ""
    checks = ""
    if expected is not None:
        checks = f"""
        i32.const {len(expected)} i32.ne if unreachable end
        i32.const 1023 i32.const {len(payload)} call $write call $newline
        """
    else:
        checks = "drop"
    return wasmtime.wat2wasm(f"""(module
      (import "goose" "format_f{bits}" (func $format (param f{bits} i32 i32) (result i32)))
      (import "goose" "write" (func $write (param i32 i32)))
      (import "goose" "newline" (func $newline))
      (memory (export "memory") 1)
      (data (i32.const 1023) "{payload}")
      (func (export "_start")
        f{bits}.const {value} i32.const {pointer} i32.const {capacity}
        call $format {checks}))""")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", default="node")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/host-format")
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    cases = [(64, "1.5", 1024, 3, "1.5"), (32, "1.25", 1024, 64, "1.25"),
             (64, "-0", 1024, 4, "-0.0"), (32, "inf", 1024, 3, "inf"),
             (64, "nan", 1024, 3, "nan")]
    cases += [(bits, "1.5", pointer, capacity, None) for bits in (32, 64)
              for pointer, capacity in ((1024, 0), (1024, 2), (1024, 65),
                                        (1024, -1), (65535, 4), (-1, 4))]
    rows = []
    for index, (bits, value, pointer, capacity, expected) in enumerate(cases):
        artifact = args.output_dir / f"case-{index}.wasm"
        artifact.write_bytes(module(bits, value, pointer, capacity, expected))
        for engine in ("v8", "wasmtime"):
            command = [args.node, str(ROOT / "scripts/run_wasm.mjs")] if engine == "v8" else [
                sys.executable, str(ROOT / "scripts/run_wasmtime.py")]
            command.append(str(artifact.resolve()))
            result = subprocess.run(command, capture_output=True, text=True, timeout=30)
            good = (result.returncode == 0 and result.stdout == f"L{expected}R\n") if expected is not None else (
                result.returncode != 0 and not result.stdout and any(word in result.stderr for word in
                    ("float formatting", "outside exported memory", "negative host address", "host address")))
            rows.append({"case": index, "bits": bits, "pointer": pointer, "capacity": capacity,
                         "engine": engine, "status": "passed" if good else "failed",
                         "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
    failures = sum(row["status"] != "passed" for row in rows)
    report = {"schema": "goose-format-host-qualification-v1", "observations": len(rows),
              "failures": failures, "hosts": {name: hashlib.sha256((ROOT / "scripts" / name).read_bytes()).hexdigest()
                                              for name in ("run_wasm.mjs", "run_wasmtime.py")}, "results": rows}
    (args.output_dir / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    for row in rows:
        if row["status"] != "passed":
            print(json.dumps(row))
    print(f"{len(rows) - failures}/{len(rows)} host-format checks passed")
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
