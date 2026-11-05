# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 43 passed C-only fixed-point verification; its final two generated C outputs match (C2 = C3). Generated C SHA-256: `b7e770818d22e90feeebe2a3c08a2ca5a458ae7b478b92c22b72a00fb584d1a9`. Compiler executable SHA-256: `c146df18e94032f322f0bf2f393d77814618a6325590c8c7c2743ce3c8cd115e`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. **Conformance is partial:** snapshot 43 passed 5,511 of 5,677 rows; 166 failed. Against snapshot 42, 13 of 5,300 shared checks improved and none regressed. All 377 new source-authored checks passed. The 166 remaining failures comprise 28 invalid-program checks and 138 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 2,272/2,272 checks each in Wasmtime and V8; all 314 curated native controls also passed. No C++ oracle was executed.

This batch corrects numeric and identity checks, literal borrowing, loop counts, initializer order and worker snapshots. The remaining failures are 28 accepted invalid programs and 138 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification details](results/2026-11-05/readonly-numbers-and-static-views/summary.json) · [Guide](../docs/GUIDE.md)
