#!/usr/bin/env python3
"""The outer driver stages native, standalone-Wasm and JS/Wasm deliverables."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build" / "bin" / "goose")
    parser.add_argument("--node", default="node")
    parser.add_argument("--cc", default="gcc")
    parser.add_argument("--emcc", help="include both C-Wasm profiles when Emscripten is available")
    args = parser.parse_args()
    (ROOT / "build").mkdir(exist_ok=True)
    profiles = [("native", ".bin")]
    if args.emcc:
        profiles += [("c-wasm", ".wasm"), ("c-wasm", ".mjs")]
    with tempfile.TemporaryDirectory(prefix="publication-test-", dir=ROOT / "build") as temporary:
        directory = Path(temporary)
        source, invalid = directory / "main.goose", directory / "invalid.goose"
        source.write_text("fn main() { print(42); }\n")
        invalid.write_text("fn main() { unknown !!! }\n")
        for backend, suffix in profiles:
            output = directory / (backend + suffix)
            stats = directory / (backend + suffix + ".json")
            emitted = directory / "generated" / (backend + suffix + ".c")
            command = [sys.executable, str(ROOT / "scripts" / "goose_wasm.py"), "build", str(source),
                       "--goose", str(args.goose.resolve()), "--backend", backend, "-o", str(output),
                       "--stats", str(stats), "--emit-c", str(emitted), "--json", "--cc", args.cc]
            if args.emcc:
                command += ["--emcc", args.emcc]
            result = subprocess.run(command, capture_output=True, text=True, timeout=180)
            assert result.returncode == 0, result.stderr
            metadata = json.loads(stats.read_text())
            module = output.with_suffix(".wasm") if backend == "c-wasm" else output
            digest = metadata["module_sha256" if backend == "c-wasm" else "output_sha256"]
            assert hashlib.sha256(module.read_bytes()).hexdigest() == digest
            assert emitted.is_file()
            run = ([str(output)] if backend == "native" else [args.node, str(output)] if suffix == ".mjs"
                   else [args.node, str(ROOT / "scripts" / "run_wasm.mjs"), str(output)])
            executed = subprocess.run(run, capture_output=True, text=True, timeout=60)
            assert executed.returncode == 0 and executed.stdout == "42\n", executed.stderr + executed.stdout
            paths = {output, module, stats, emitted}
            before = {path: path.read_bytes() for path in paths}
            failed = command.copy()
            failed[3] = str(invalid)
            rejected = subprocess.run(failed, capture_output=True, text=True, timeout=180)
            assert rejected.returncode != 0
            assert all(path.read_bytes() == value for path, value in before.items())
            collision = subprocess.run(command + ["--stats", str(module)], capture_output=True, text=True, timeout=60)
            assert collision.returncode != 0 and "distinct paths" in collision.stderr
            assert all(path.read_bytes() == value for path, value in before.items())
            print(f"PASS {backend}{suffix}: execution, digest, emitted C, failed-build preservation, collision rejection")
    print(f"{len(profiles)} publication profiles passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
