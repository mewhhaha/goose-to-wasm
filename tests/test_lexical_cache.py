#!/usr/bin/env python3
"""Exercise the patched lexer against cold scans with actual retained state."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=ROOT / "build/source")
    parser.add_argument("--disable-leak-check", action="store_true",
                        help="disable LeakSanitizer in environments that trace child processes")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
        executable = Path(directory) / "lexical-cache"
        subprocess.run(["c++", "-std=c++20", "-O1", "-g", "-fsanitize=address,undefined",
                        "-fno-omit-frame-pointer", "-I", str(args.source_dir / "src"),
                        str(ROOT / "tests/lexical_cache.cpp"), "-o", str(executable)], check=True)
        environment = os.environ.copy()
        if args.disable_leak_check:
            environment["ASAN_OPTIONS"] = environment.get("ASAN_OPTIONS", "") + ":detect_leaks=0"
        subprocess.run([str(executable)], check=True, timeout=60, env=environment)
