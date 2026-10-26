#!/usr/bin/env python3
"""Check sparse static data, deterministic modules, and memory exhaustion.

The payload checks guard the compiler's size/compilation-cost regression; the
native oracle and both Wasm engines independently check language-visible data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from run_differential import execute, save_log

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = "0 0 0 0\n255 65535 1048577 1048577\nA\0B cafétail\n9 0 0\n"


def unsigned(data, offset):
    value = shift = 0
    while True:
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
        shift += 7
        if shift > 35:
            raise ValueError("invalid u32 LEB")


def sections(data):
    assert data[:8] == b"\0asm\1\0\0\0", "invalid Wasm header"
    offset = 8
    result = {}
    while offset < len(data):
        kind = data[offset]
        length, offset = unsigned(data, offset + 1)
        payload = data[offset:offset + length]
        assert len(payload) == length, "truncated section"
        if kind:
            assert kind not in result, "duplicate section"
            result[kind] = payload
        offset += length
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / "build/bin/goose")
    parser.add_argument("--node", default="node")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/memory-tests")
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    args.goose = args.goose.resolve()
    fixture = ROOT / "tests/fixtures/static_memory.goose"
    rows = []

    def record(name, test):
        try:
            detail = test() or {}
            rows.append({"name": name, "status": "pass", **detail})
        except (AssertionError, OSError, ValueError, subprocess.TimeoutExpired) as error:
            rows.append({"name": name, "status": "fail", "error": str(error)})
        row = rows[-1]
        print(row["status"].upper(), name, row.get("error", ""), flush=True)

    for level in (0, 2):
        for backend in ("native", "direct"):
            directory = output / f"O{level}" / backend
            directory.mkdir(parents=True, exist_ok=True)
            artifact = directory / ("program.bin" if backend == "native" else "program.wasm")
            command = [sys.executable, ROOT / "scripts/goose_wasm.py", "build", fixture,
                       "--goose", args.goose, "--backend", backend, f"-O{level}",
                       "--no-cache", "--offline", "-o", artifact]

            def build():
                result, seconds = execute(command, cwd=ROOT)
                save_log(directory, "compile", command, result)
                assert result.returncode == 0, result.stdout + result.stderr
                data = artifact.read_bytes()
                if backend == "direct":
                    parsed = sections(data)
                    assert len(data) < 32768, f"serialized zero reservations: {len(data)} bytes"
                    assert len(parsed.get(11, b"")) < 2048, "oversized initializer payload"
                    assert b"A\0B caf\xc3\xa9" in parsed[11], "literal bytes changed"
                    again = directory / "again.wasm"
                    repeated = [args.goose, fixture, "--target", "wasm-direct", f"-O{level}",
                                "--offline", "-o", again]
                    p, _ = execute(repeated, cwd=ROOT)
                    assert p.returncode == 0, p.stdout + p.stderr
                    assert data == again.read_bytes(), "module emission is nondeterministic"
                return {"seconds": seconds, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}

            record(f"O{level}/{backend}/build", build)
            if rows[-1]["status"] != "pass":
                continue
            for engine in (("native",) if backend == "native" else ("v8", "wasmtime")):
                def run():
                    cmd = ([artifact] if engine == "native" else
                           [args.node, ROOT / "scripts/run_wasm.mjs", artifact] if engine == "v8" else
                           [sys.executable, ROOT / "scripts/run_wasmtime.py", artifact])
                    result, seconds = execute(cmd, cwd=directory)
                    save_log(directory, engine, cmd, result)
                    assert result.returncode == 0, result.stderr
                    assert result.stdout == EXPECTED, repr(result.stdout)
                    return {"stdout": result.stdout, "seconds": seconds}
                record(f"O{level}/{engine}/initialization", run)

    def limit():
        target = output / "preserved.wasm"
        previous = (output / "O2/direct/program.wasm").read_bytes()
        target.write_bytes(previous)
        cmd = [args.goose, fixture, "--target", "wasm-direct", "--offline",
               "--wasm-initial-pages", "1", "--wasm-max-pages", "16", "-o", target]
        result, _ = execute(cmd, cwd=ROOT)
        save_log(output, "static-limit", cmd, result)
        assert result.returncode != 0, "oversized static data was accepted"
        assert "exceeds the configured linear-memory limit" in result.stdout + result.stderr
        assert target.read_bytes() == previous, "failed build replaced a valid output"

    record("static-limit-and-output-preservation", limit)
    def overflow(name, text, diagnostic):
        source = output / (name + ".goose")
        source.write_text(text)
        target = output / (name + "-preserved.wasm")
        previous = (output / "O2/direct/program.wasm").read_bytes()
        target.write_bytes(previous)
        cmd = [args.goose, source, "--target", "wasm-direct", "--offline", "-o", target]
        result, _ = execute(cmd, cwd=ROOT)
        save_log(output, name, cmd, result)
        assert result.returncode != 0, "an unrepresentable array layout was accepted"
        assert diagnostic in result.stdout + result.stderr
        assert target.read_bytes() == previous, "overflowing layout replaced a valid output"
    record("fixed-layout-multiplication-overflow", lambda: overflow(
        "layout-overflow", "var huge: i64[2305843009213693952] = [0; 2305843009213693952];\n"
        "fn main() { print(huge.len); }\n", "fixed array exceeds the configured linear-memory limit"))
    record("limited-capacity-narrowing-overflow", lambda: overflow(
        "capacity-overflow", "var huge: i64[..4294967296] = [];\nfn main() { print(huge.cap); }\n",
        "array capacity exceeds the direct address range"))
    failures = sum(row["status"] != "pass" for row in rows)
    report = {"schema": "goose-memory-qualification-v1", "observations": len(rows),
              "failures": failures, "compiler_sha256": hashlib.sha256(args.goose.read_bytes()).hexdigest(),
              "results": rows}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"{len(rows) - failures}/{len(rows)} passed; {output / 'report.json'}")
    return int(failures != 0)


if __name__ == "__main__":
    sys.exit(main())
