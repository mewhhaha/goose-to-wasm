# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 50 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `4ee44216acaf19cac7094015a574a354ea90c38a86f381da2417b82b80fd6065`. Compiler executable SHA-256: `dadf054e9784bd3dfea0b4c54263ca7cd8391e7d181515b7fc058a08d300d349`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 50 passed 7,259 of 7,371 rows; 112 failed. Against snapshot 49, 2 of 7,235 shared checks improved and none regressed. All 136 new source-authored checks passed. The 112 remaining failures comprise 6 invalid-program checks and 106 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,078/3,078 checks each in Wasmtime and V8; all 1,202 curated native controls also passed.

Owned value copies drop top-level const; references and slice contents keep their access rules. Array-to-slice conversion now carries the pointer and logical length through forwarded tuples. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 106 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. No C++ oracle was executed. [Qualification details](results/2026-11-07/plain-values-and-forwarded-views/summary.json) · [Guide](../docs/GUIDE.md)
