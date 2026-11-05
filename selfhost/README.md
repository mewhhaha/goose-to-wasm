# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 40 passed C-only fixed-point verification. Generated C SHA-256: `54ca14dd2ce2012c45950fcae3c03c77069e5a909ee30ee238052d2e00346e43`. Compiler executable SHA-256: `89b89d0667c2b92e01f38c29a3e1910d18e5ef7fe4e13c12a6daff1ecce15940`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. **Conformance is partial:** snapshot 40 passed 4,798 of 5,043 rows; 245 failed. Against snapshot 39, 16 of 5,043 shared checks improved and none regressed. The curated Wasm corpus passed 1,952/1,952 checks each in Wasmtime and V8.

It separates global value, type and function names, and fixes enum storage checks and reference matches. Remaining gaps include 41 accepted invalid programs and 204 runtime contracts that fail to compile or execute. Variable images, lifetimes and control flow remain incomplete. [Qualification details](results/2026-11-05/names-and-enums/summary.json) · [Guide](../docs/GUIDE.md)
