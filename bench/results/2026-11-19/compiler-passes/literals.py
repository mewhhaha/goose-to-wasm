"""Compare native and Wasmtime compiler processes on programs containing distinct strings."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "bench"))
from selfhost_comparison import WASM_FLAGS, identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("work", "stdlib", "host", "native_before", "native_after", "wasm_before", "wasm_after"):
        parser.add_argument(key, type=lambda s: Path(s).resolve())
    parser.add_argument("--cpu", type=int, default=6)
    parser.add_argument("--rounds", type=int, default=7)
    args = parser.parse_args()
    os.sched_setaffinity(0, {args.cpu})
    args.work.mkdir(parents=True, exist_ok=True)
    commands = {}
    report = dict(cpu=args.cpu, host=identity(args.host), flags=WASM_FLAGS, compilers={}, inputs={}, samples=[])
    for label in ("native_before", "wasm_before", "wasm_after", "native_after"):
        compiler = getattr(args, label)
        report["compilers"][label] = identity(compiler)
        command = [compiler]
        if label.startswith("wasm"):
            cache = args.work / (label + ".cwasm")
            command = [args.host, compiler, "--cache", cache, "--"]
            subprocess.run([*command, "--version"], check=True, stdout=subprocess.DEVNULL)
        commands[label] = command
    for unique in (512, 2048, 8192):
        words = [f"label-{n:06d}" for n in range(unique)]
        words.extend((words[0], words[unique // 2]))
        literals = ", ".join(map(json.dumps, words))
        source = args.work / f"words-{unique}.goose"
        source.write_text("fn main() { var total: i64 = 0; for word in [" + literals
                          + "] { total += word[10] as i64; } print(total); }\n")
        expected = args.work / "reference.wasm"
        flags = [source, "--stdlib", args.stdlib, *WASM_FLAGS]
        subprocess.run([args.native_before, *flags, "-o", expected], check=True)
        checksum = sum(ord(word[10]) for word in words)
        assert subprocess.check_output([args.host, expected, "--no-cache"]) == f"{checksum}\n".encode()
        reference = identity(expected)
        report["inputs"][unique] = dict(source=identity(source), output=reference, checksum=checksum)
        for i in range(args.rounds):
            labels = list(commands)
            if i % 2:
                labels.reverse()
            for label in labels:
                output = args.work / "program.wasm"
                output.unlink(missing_ok=True)
                start = time.perf_counter_ns()
                subprocess.run([*commands[label], *flags, "-o", output], check=True)
                elapsed = time.perf_counter_ns() - start
                assert identity(output) == reference
                report["samples"].append(dict(unique=unique, case=label, round=i+1, wall_ns=elapsed))
        print(unique, "literals verified", flush=True)
        (args.work / "measurements.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
