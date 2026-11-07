# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 51 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `0f2560354854533bd498d6be60deed82752c50b6ef48819c6de9cba28fb8c146`. Compiler executable SHA-256: `e67ea31056553e4d0752fd9ef66ba0a1d6216811d757340c6167f7240ebdd02f`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 51 passed 7,327 of 7,435 rows; 108 failed. Against snapshot 50, 4 of 7,371 shared checks improved and none regressed. All 64 new source-authored checks passed. The 108 remaining failures comprise 6 invalid-program checks and 102 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,110/3,110 checks each in Wasmtime and V8; all 1,234 curated native controls also passed.

Enum case dispatch gives IF, MATCH, block and loop arguments the selected borrowing context, keeps const authority and evaluates real arguments once. Overload trials use payload types without inventing temporary storage. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 102 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. No C++ oracle was executed. [Qualification details](results/2026-11-07/contextual-enum-dispatch/summary.json) · [Guide](../docs/GUIDE.md)
