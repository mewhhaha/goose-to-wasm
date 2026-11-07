# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 46 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `4fdbb47e3326835eb7b9fa7e939c84050d57a2e90ff047fc9d7f643c50e3b973`. Compiler executable SHA-256: `c081b77fa243d6a5cf3df7e45146c06e02b0598db268ac015d99022db9d387b9`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. **Conformance is partial:** snapshot 46 passed 6,403 of 6,537 rows; 134 failed. Against snapshot 45, 4 of 6,389 shared checks improved and none regressed. All 148 new source-authored checks passed. The 134 remaining failures comprise 12 invalid-program checks and 122 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 2,676/2,676 checks each in Wasmtime and V8; all 770 curated native controls also passed. No C++ oracle was executed.

This batch adds bounded flat relative-image access and preserves conversions and mutations through completed early blocks. The remaining failures are 12 accepted invalid programs and 122 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification details](results/2026-11-05/bounded-images-and-early-results/summary.json) · [Guide](../docs/GUIDE.md)
