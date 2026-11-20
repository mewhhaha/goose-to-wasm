"""Measure the lifetime checker while compiling ten calls of increasing width on Linux."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import resource
import subprocess
import sys

HERE = Path(__file__).resolve().parent
PROBES = HERE.parent.parent / "2026-11-19/lifetime-evaluator-frames/tools"
sys.path.insert(0, str(PROBES))
from phases import phase_counts


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def program(width):
    params = ", ".join(f"a{i}: i64" for i in range(width))
    args = ", ".join(map(str, range(width)))
    call = f"    print(wide({args}));\n"
    return f"fn wide({params}) -> i64 {{ return a0 + a{width-1}; }}\nfn main() {{\n" + call * 10 + "}\n"


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("previous", "current", "native_reference", "host", "stdlib", "work"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--cpu", type=int, default=3)
    parser.add_argument("--rounds", type=int, default=8)
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("rounds must be positive")
    work = args.work.resolve()
    work.mkdir(parents=True)
    resource.setrlimit(resource.RLIMIT_STACK, (256 << 20, resource.getrlimit(resource.RLIMIT_STACK)[1]))
    os.sched_setaffinity(0, {args.cpu})
    host = args.host.resolve()
    native = args.native_reference.resolve()
    probe = PROBES / "clock.c"
    library = work / "clock.so"
    subprocess.run(["cc", "-O2", "-fPIC", "-shared", probe, "-o", library], check=True)
    trace = work / "clock.bin"
    env = dict(os.environ, LD_PRELOAD=str(library), GOOSE_PHASE_LOG=str(trace))
    modules = {"before": args.previous.resolve(), "after": args.current.resolve()}
    command = {key: [host, mod, "--cache", work / f"{key}.cwasm", "--"] for key, mod in modules.items()}
    for prefix in command.values():
        subprocess.run([*prefix, "--version"], check=True, stdout=subprocess.DEVNULL)

    seed = 1132
    rng = random.Random(seed)
    report = dict(modules={k: sha(v) for k, v in modules.items()}, native_reference=sha(native),
                  host=sha(host), probe=sha(probe), cpu=args.cpu, seed=seed, rounds=args.rounds,
                  flags=["--target", "wasm-direct", "-O2"], widths={})
    out = work / "out.wasm"
    stats = work / "stats.json"
    for width in (8, 32, 128, 512):
        src = work / f"wide-{width}.goose"
        src.write_text(program(width))
        flags = [src, "--stdlib", args.stdlib.resolve(), *report["flags"], "-o", out]
        subprocess.run([native, *flags], check=True)
        expected = sha(out)
        executed = subprocess.run([host, out], capture_output=True, check=True)
        assert executed.stdout == (f"{width-1}\n" * 10).encode() and not executed.stderr
        samples = []
        report["widths"][width] = dict(source=sha(src), output=expected, stdout=executed.stdout.decode(), samples=samples)
        for r in range(args.rounds):
            order = list(modules)
            rng.shuffle(order)
            for version in order:
                for artifact in (trace, stats, out):
                    artifact.unlink(missing_ok=True)
                subprocess.run([*command[version], *flags, "--wasm-stats", stats], env=env, check=True)
                assert sha(out) == expected
                counts, clocks = phase_counts(trace, json.loads(stats.read_bytes()))
                samples.append(dict(round=r+1, compiler=version, phases=counts, clock_samples=clocks))
        (work / "report.json").write_text(json.dumps(report) + "\n")
        print(f"{width} parameters: {len(samples)} byte-identical builds", flush=True)


if __name__ == "__main__":
    run()
