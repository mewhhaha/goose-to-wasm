#!/usr/bin/env python3
"""Import syntax, destroy its owner, and run real checking/emission under ASan."""
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
    build = args.build_dir.resolve()
    source, native = build / "source", build / "native"
    from run_differential import cases
    fixtures = sorted({ROOT / "tests/fixtures" / (case.fixture + ".goose") for case in cases()})
    frontend = [source / "test" / name for name in (
        "syntax/parser_all.goose", "syntax/generic_shadowing.goose",
        "typing/const_for_variants.goose",
    )]
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
        executable = Path(directory) / "syntax-importer"
        command = ["c++", "-std=c++20", "-O0", "-g1", "-fsanitize=address,undefined",
                   "-fno-omit-frame-pointer", "-pthread", "-I", str(source / "src"),
                   "-I", str(ROOT / "compiler"), "-I", str(source / "third_party/subprocess"),
                   "-I", str(native / "generated"), "-isystem", str(native / "tcc/api"),
                   str(ROOT / "tests/syntax_importer.cpp"),
                   str(native / "CMakeFiles/goose.dir/src/process.cpp.o"),
                   str(native / "CMakeFiles/goose.dir/src/progress.cpp.o"),
                   str(native / "libgoose_shaderc.a"), str(native / "libtcc.a"),
                   "-ldl", "-lm", "-o", str(executable)]
        subprocess.run(command, check=True)
        environment = os.environ.copy()
        environment["UBSAN_OPTIONS"] = environment.get("UBSAN_OPTIONS", "") + ":halt_on_error=1:print_stacktrace=1"
        if args.disable_leak_check:
            environment["ASAN_OPTIONS"] = environment.get("ASAN_OPTIONS", "") + ":detect_leaks=0"
        subprocess.run([str(executable), str(source / "stdlib"), *map(str, fixtures),
                        "--frontend-only", *map(str, frontend)],
                       check=True, timeout=300, env=environment)
