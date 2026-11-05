# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 37 passed C-only fixed-point verification. Generated C SHA-256: `18abc2ee8d0f77a39dccab2f173b080b0f85e88bdee664a47108e311991da116`. Compiler executable SHA-256: `a89f4c447a7eea5950f510301cac6be0b7c35d37690da9182952cac42d2b0391`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. **Conformance is partial:** snapshot 37 passed 4,717 of 5,028 rows; 311 failed. Against snapshot 34, 29 of 5,021 shared checks improved and none regressed; seven new literal-kind checks all passed. The curated Wasm corpus passed 1,946/1,946 checks each in Wasmtime and V8.

It adds natural result projection and fixes relative receivers, native array views, printing and validation. Remaining gaps include 61 accepted invalid types and 250 runtime contracts that fail to compile or execute, including variable images, varints, lifetimes and default names. [Qualification details](results/2026-11-05/rendering-and-results/summary.json) · [Guide](../docs/GUIDE.md)
