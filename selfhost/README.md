# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 45 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `89feb6d5fba53f3bd2c36f5e00be164a53588856d2dfad8f0f021f647e6edebb`. Compiler executable SHA-256: `45e640b7f929b101de2c4ca2fe8f2299217e91794900afd7f014aaea74bd5783`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. **Conformance is partial:** snapshot 45 passed 6,251 of 6,389 rows; 138 failed. Against snapshot 44, 8 of 6,061 shared checks improved and none regressed. All 328 new source-authored checks passed. The 138 remaining failures comprise 12 invalid-program checks and 126 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 2,618/2,618 checks each in Wasmtime and V8; all 680 curated native controls also passed. No C++ oracle was executed.

This batch preserves float width, element-reference identity, readonly storage and whole-local result ownership. The remaining failures are 12 accepted invalid programs and 126 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification details](results/2026-11-05/constant-width-and-reference-checks/summary.json) · [Guide](../docs/GUIDE.md)
