# Goose in Goose

The compiler is written in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The compiler and standard library are installed in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output. Goose emission defaults to `-O2`; the C build uses `-std=gnu11 -O2 -lm -ldl -pthread`.

An optional Clang IR profile is used only when its C hash, target triple, Clang major version, C basename and base flags match, and its data checksum is valid. If the profile is missing, mismatched or fails to compile, bootstrap builds without it and records the reason. The supplied profile targets Clang 23 and `x86_64-pc-linux-gnu`; it was trained on the compiler itself and two feature fixtures, excluding the eleven timed programs.

Two independent public output roots, one using defaults and one explicit options, passed `--verify` with `profile_used: true`. Both produced executable SHA-256 `9a0450a452f6dcc0c6ad698fdeb9af6be599c7e8ffdb2437364a6f360145489d` and generated C SHA-256 `191a6b540a7c59ccdd0de5ac32199eea958bb19121cd98a1bfe269c13fc2aea6`. [Qualification](results/2026-11-08/compiler-throughput-58/README.md)

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases. Snapshot 58 passed 7,955 of 8,055 rows; all 184 new rows passed, and the 7,871 previous results and phases were unchanged. The 100 known gaps comprise six invalid programs accepted and 94 runtime contracts refused during compilation. The curated corpus passed 3,370 Wasm checks in each of Wasmtime and V8 and 1,410 native controls. All 45 native runtime checks and 16 stack-guard profiles passed.

A C++ reference guided the initial port; bootstrap and the frozen contracts do not execute it. The previous C++ compiler remains a benchmark competitor. These contracts cover selected behavior, not all Goose programs. [Results and limitations](results/2026-11-08/compiler-throughput-58/README.md) · [Guide](../docs/GUIDE.md)
