# Goose in Goose

The compiler is written in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The compiler and standard library are installed in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output. Goose emission defaults to `-O2`; the C build uses `-std=gnu11 -O2 -lm -ldl -pthread`. For development builds, `--jobs N` compiles generated C that marks its units (`native/units.h`) as N program units and a runtime unit in parallel, without the profile; C from an older seed still compiles whole. The default, one unit, keeps the release build and its profile.

An optional Clang IR profile is used only when its C hash, target triple, Clang major version, C basename and base flags match, and its data checksum is valid. If the profile is missing, mismatched or fails to compile, bootstrap builds without it and records the reason. The supplied profile targets Clang 23 and `x86_64-pc-linux-gnu`; it was trained on the compiler itself and two feature fixtures, excluding the eleven timed programs.

For snapshot 63, two independent public output roots, one using defaults and one explicit options, passed `--verify` with `profile_used: true`. Both produced executable SHA-256 `10ade9d54abd059038d05cb76d1f81f9c89b9254c2f3529794995e298518ab56` and generated C SHA-256 `28f1af08daba0f4de86b6f5e2c5ef1adfd25f5ce2921162ea67fa5df78998970`. [Snapshot 63](results/2026-11-14/snapshot-63/README.md) · [Snapshot 62](results/2026-11-14/snapshot-62/README.md) · [Earlier qualification](results/2026-11-11/cli-outputs-60/README.md) · [Throughput qualification](results/2026-11-11/compiler-throughput-59/README.md)

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases. Snapshot 59 passed 7,955 of 8,055 rows, and every row matches snapshot 58. The 100 known gaps comprise six invalid programs accepted and 94 runtime contracts refused during compilation. The curated corpus passed 3,370 Wasm checks in each of Wasmtime and V8 and 1,410 native controls. All 45 native runtime checks and 16 stack-guard profiles passed.

Modules found through `--stdlib` are libraries: their function bodies are lexed, parsed and checked only when the program reaches them. Unused functions in user sources are still checked.

A C++ reference guided the initial port; bootstrap and the frozen contracts do not execute it. The previous C++ compiler remains a benchmark competitor. These contracts cover selected behavior, not all Goose programs. [Results and limitations](results/2026-11-11/compiler-throughput-59/README.md) · [Guide](../docs/GUIDE.md)
