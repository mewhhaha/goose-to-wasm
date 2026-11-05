# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 39 passed C-only fixed-point verification. Generated C SHA-256: `b840947e3a0b12bdf43f34ed4c7dbaa5a89daaf4f7f43d530703c1aa627e9e0c`. Compiler executable SHA-256: `252a3bd12fc0cec06b151a5756380dd9f083ffe1a0fa0ea4d52e2b5c6bf23421`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. **Conformance is partial:** snapshot 39 passed 4,782 of 5,043 rows; 261 failed. Against snapshot 38, 10 of 5,043 shared checks improved and none regressed. The curated Wasm corpus passed 1,952/1,952 checks each in Wasmtime and V8.

It fixes returned local construction, nonlocal target contexts and native lowering of divergent tails. Remaining gaps include 47 accepted invalid programs and 214 runtime contracts that fail to compile or execute. Variable images, lifetimes and control flow remain incomplete. [Qualification details](results/2026-11-05/returns-and-contexts/summary.json) · [Guide](../docs/GUIDE.md)
