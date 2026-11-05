# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 41 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `7ec5c7ef91e5a157c6a00c8b25d4b037765f485f9f3499c33b3f230206da1e34`. Compiler executable SHA-256: `cef0fa1fafc79501536fc150e1f62ae478b544043b335685610f992f34352ede`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. **Conformance is partial:** snapshot 41 passed 4,914 of 5,118 rows; 204 failed. Against snapshot 40, 41 of 5,043 shared checks improved and none regressed. All 75 new source-authored checks passed. The 204 remaining failures comprise 38 invalid-program checks and 166 runtime contracts. The curated Wasm corpus passed 1,993/1,993 checks each in Wasmtime and V8; all 34 curated native controls also passed. No C++ oracle was executed.

Snapshot 41 adds canonical variable and runtime-limited images, byte-cursor copy and iteration, aggregate compound-assignment ordering, full-width free integer and stopping arguments, canonical stack diagnostics and stats, captured-specialization environment tracking, and delayed fixed Ref/Slice bindings. Remaining gaps include 38 accepted invalid programs and 166 runtime contracts that fail to compile or execute. Lifetimes, control flow and native image operations remain incomplete. [Qualification details](results/2026-11-05/storage-and-captures/summary.json) · [Guide](../docs/GUIDE.md)
