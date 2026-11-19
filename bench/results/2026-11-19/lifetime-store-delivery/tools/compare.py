"""Compare structural lifetime traces emitted by two instrumented compilers."""

import argparse
import subprocess
from pathlib import Path


def check(compiler, source, stdlib):
    process = subprocess.run(
        [compiler, source, "--stdlib", stdlib, "--target", "wasm-direct", "--check"],
        capture_output=True,
        timeout=600,
    )
    if process.returncode < 0:
        raise RuntimeError(f"{compiler} exited on signal {-process.returncode} while checking {source}")
    trace = []
    diagnostics = []
    for line in process.stderr.splitlines(keepends=True):
        if line.startswith(b"LIFEFP "):
            trace.append(line)
        else:
            diagnostics.append(line)
    begins = [line for line in trace if line.startswith(b"LIFEFP begin ")]
    end = [line for line in trace if not line.startswith(b"LIFEFP begin ")]
    return (process.returncode, process.stdout, diagnostics), begins, end


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("sources", type=Path, nargs="+")
    parser.add_argument("--stdlib", type=Path, default=Path("stdlib"))
    args = parser.parse_args()
    if not args.stdlib.is_dir():
        parser.error(f"Missing standard library directory: {args.stdlib}")
    failed = False
    for source in args.sources:
        if not source.is_file():
            parser.error(f"Missing source: {source}")
        old, starts, end = check(args.baseline.resolve(), source, args.stdlib)
        new, other_starts, other_end = check(args.candidate.resolve(), source, args.stdlib)
        match = old == new and starts[:len(other_starts)] == other_starts and end == other_end
        if old[0] == 0 and not end:
            raise ValueError(f"No lifetime trace in successful baseline check of {source}")
        status = "matched" if match else "DIFFERENT"
        print(f"{source}: {status}, {len(starts)} -> {len(other_starts)} discovery passes")
        if not match:
            failed = True
    raise SystemExit(int(failed))


if __name__ == "__main__":
    main()
