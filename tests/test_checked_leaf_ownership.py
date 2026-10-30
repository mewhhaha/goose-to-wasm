#!/usr/bin/env python3
"""Destroy checked-leaf producers and cache entries under ASan and UBSan."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build")
    parser.add_argument("--disable-leak-check", action="store_true")
    args = parser.parse_args()
    source, native = args.build_dir.resolve() / "source", args.build_dir.resolve() / "native"
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
        executable = Path(directory) / "checked-leaf-cache"
        command = ["c++", "-std=c++20", "-O0", "-g1", "-fsanitize=address,undefined",
                   "-fno-omit-frame-pointer", "-pthread", "-I", str(source / "src"),
                   "-I", str(ROOT / "compiler"), "-I", str(source / "third_party/subprocess"),
                   "-I", str(native / "generated"), "-isystem", str(native / "tcc/api"),
                   str(ROOT / "tests/checked_leaf_cache.cpp"),
                   str(native / "CMakeFiles/goose.dir/src/process.cpp.o"),
                   str(native / "CMakeFiles/goose.dir/src/progress.cpp.o"),
                   str(native / "libgoose_shaderc.a"), str(native / "libtcc.a"),
                   "-ldl", "-lm", "-o", str(executable)]
        subprocess.run(command, check=True)
        env = dict(os.environ)
        env["UBSAN_OPTIONS"] = env.get("UBSAN_OPTIONS", "") + ":halt_on_error=1:print_stacktrace=1"
        if args.disable_leak_check:
            env["ASAN_OPTIONS"] = env.get("ASAN_OPTIONS", "") + ":detect_leaks=0"
        subprocess.run([str(executable), str(ROOT / "tests/fixtures/checked_leaves.goose"),
                        str(ROOT / "tests/fixtures/scalar_callers.goose")],
                       check=True, timeout=180, env=env)
