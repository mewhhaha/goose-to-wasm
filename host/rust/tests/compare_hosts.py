#!/usr/bin/env python3
"""Run Goose programs on the Rust host and on scripts/run_wasmtime.py and compare.

Each source is compiled for a 32-bit and for a 64-bit memory; a module's
stdout, exit code and stderr must be the same from both hosts. Run from the
repository root with the Python that has the wasmtime package:

    .venv/bin/python host/rust/tests/compare_hosts.py examples/*.goose
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", nargs="+", type=Path)
    parser.add_argument("--compiler", type=Path, default=ROOT / "build/q-m64/bootstrap/bin/goose")
    parser.add_argument("--host", type=Path, default=ROOT / "host/rust/target/release/goose-wasmtime")
    parser.add_argument("--work", type=Path, required=True, help="directory for the compiled modules")
    parser.add_argument("--stdin", default="", help="the programs' input")
    parser.add_argument("--limit", type=int, help="stop after this many sources that compile")
    parser.add_argument("--jobs", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=300)
    args = parser.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)

    def compiled(source: Path, flags: list[str], tag: str) -> Path | None:
        module = args.work / f"{source.stem}.{tag}.wasm"
        done = subprocess.run([args.compiler, source, "--stdlib", "stdlib", "--target", "wasm-direct", "-O2", *flags, "-o", module],
                              cwd=ROOT, capture_output=True)
        return module if done.returncode == 0 and module.is_file() else None

    def ran(command: list) -> tuple:
        try:
            done = subprocess.run(command, cwd=ROOT, input=args.stdin.encode(), capture_output=True, timeout=args.timeout)
        except subprocess.TimeoutExpired:
            return ("timeout", b"", b"")
        return (done.returncode, done.stdout, done.stderr)

    def compare(module: Path) -> tuple[Path, tuple, tuple]:
        return module, ran([sys.executable, ROOT / "scripts/run_wasmtime.py", module]), ran([args.host, module])

    modules, sources, refused = [], 0, []
    for source in args.sources:
        if args.limit is not None and sources >= args.limit:
            break
        pair = [compiled(source, [], "m32"), compiled(source, ["--wasm-memory64"], "m64")]
        if None in pair:
            refused.append(source.name)
            continue
        sources += 1
        modules += pair
    with ThreadPoolExecutor(args.jobs) as pool:
        results = list(pool.map(compare, modules))
    differences = 0
    kinds: dict = {}
    for module, python, rust in results:
        kinds[python[0]] = kinds.get(python[0], 0) + 1
        if python != rust:
            differences += 1
            print(f"DIFFERENT {module.name}")
            for name, a, b in zip(("exit code", "stdout", "stderr"), python, rust):
                if a != b:
                    print(f"  {name}: python {a!r:.300}\n  {name}: rust   {b!r:.300}")
    print(f"{sources} sources compiled ({len(refused)} did not), {len(modules)} modules run on both hosts, {differences} differences")
    print("exit codes from the Python runner:", ", ".join(f"{code}: {count}" for code, count in sorted(kinds.items(), key=str)))
    return 1 if differences else 0


if __name__ == "__main__":
    sys.exit(main())
