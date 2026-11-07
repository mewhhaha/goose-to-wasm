# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 48 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `b8133b5120a3b6a0d393bc260ed2ee8dbf2a880cb3dace8a093e1c03125f3d65`. Compiler executable SHA-256: `10b644041666eddb23349a2eb50efd2da0594113f30fb3516cebcb0dd0d37543`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 48 passed 7,003 of 7,121 rows; 118 failed. Against snapshot 47, 12 of 6,997 shared checks improved and none regressed. All 124 new source-authored checks passed. The 118 remaining failures comprise 6 invalid-program checks and 112 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 2,970/2,970 checks each in Wasmtime and V8; all 1,060 curated native controls also passed. No C++ oracle was executed.

This batch checks exact nonlocal targets through cached and recursive calls, replacing the old context walk. Native controls that always return no longer allocate an unused result. The remaining failures are 6 accepted invalid programs and 112 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification details](results/2026-11-07/exact-nonlocal-targets/summary.json) · [Guide](../docs/GUIDE.md)
