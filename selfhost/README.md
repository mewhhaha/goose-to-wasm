# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 49 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `6213108e2780136a86f62eda3e06abcd0f74443d8a2f626be3c60be3e1941080`. Compiler executable SHA-256: `9b84b13667239a7e1c57f7b4b768542faff44325edcc2b26e3038d299d2d334b`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 49 passed 7,121 of 7,235 rows; 114 failed. Against snapshot 48, 4 of 7,121 shared checks improved and none regressed. All 114 new source-authored checks passed. The 114 remaining failures comprise 6 invalid-program checks and 108 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,010/3,010 checks each in Wasmtime and V8; all 1,134 curated native controls also passed. No C++ oracle was executed.

Multiassignment evaluates the right-hand side once into a hidden tuple, then performs ordinary assignments in sequence; fixed reference results are snapshotted before writes. The native backend admits a bounded self-relative Row array that constructs directly in its receiving region and tracks exact committed bounds. Admission is narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 108 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification details](results/2026-11-07/value-and-receiver-contracts/summary.json) · [Guide](../docs/GUIDE.md)
