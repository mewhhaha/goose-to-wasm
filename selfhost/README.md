# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 38 passed C-only fixed-point verification. Generated C SHA-256: `75453510d74da0fce4d2b2acca7e3157c7833e01b1d5acbee712f08efa3fc8a3`. Compiler executable SHA-256: `46a68ed99cb3f01ce0cf642666ea88888f3552f3dbad990e9e097cbabf30df51`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. **Conformance is partial:** snapshot 38 passed 4,772 of 5,043 rows; 271 failed. Against snapshot 37, 40 of 5,028 shared checks improved and none regressed; 15 new flow and result-channel checks all passed. The curated Wasm corpus passed 1,952/1,952 checks each in Wasmtime and V8.

It fixes copying array arguments, integer inference, varint records and flow checks for loops, defaults and nested calls, and reduces generated Wasm code. Remaining gaps include 47 accepted invalid programs and 224 runtime contracts that fail to compile or execute. Variable images, lifetimes and control flow remain incomplete. [Qualification details](results/2026-11-05/flow-and-copying/summary.json) · [Guide](../docs/GUIDE.md)
