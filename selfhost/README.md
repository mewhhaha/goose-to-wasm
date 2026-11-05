# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 44 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `bca2cbad6f35d44b315e2052b1a5dfbe06d2f90bab0d9f2eaa97e7be72486602`. Compiler executable SHA-256: `3130d2f26a8eb028cb192b88e402d30e35318799d0e06e0be811c91d5dcb2e34`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. **Conformance is partial:** snapshot 44 passed 5,915 of 6,061 rows; 146 failed. Against snapshot 43, 20 of 5,677 shared checks improved and none regressed. All 384 new source-authored checks passed. The 146 remaining failures comprise 18 invalid-program checks and 128 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 2,454/2,454 checks each in Wasmtime and V8; all 516 curated native controls also passed. No C++ oracle was executed.

This batch corrects default-callback returns, readonly iteration, tail references, pool rebinding, scalar relative cells and numeric control values. The remaining failures are 18 accepted invalid programs and 128 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification details](results/2026-11-05/relative-cells-and-control-values/summary.json) · [Guide](../docs/GUIDE.md)
