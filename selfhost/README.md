# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 47 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `52aa5342f183677c02843a514704107b3ecef2db2a8767b44f25759f33664a53`. Compiler executable SHA-256: `17890c2354938252cbea8015483be24fcf0add3df4b9bae0d04f5ec2d75fc82c`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 47 passed 6,867 of 6,997 rows; 130 failed. Against snapshot 46, 4 of 6,537 shared checks improved and none regressed. All 460 new source-authored checks passed. The 130 remaining failures comprise 8 invalid-program checks and 122 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 2,908/2,908 checks each in Wasmtime and V8; all 998 curated native controls also passed. No C++ oracle was executed.

This batch fixes pending-element completion, resizable variant bindings, overload ranking and untyped function arguments. Wasm resizable payloads retain their contents and stable field references across copies and replacement. The remaining failures are 8 accepted invalid programs and 122 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification details](results/2026-11-07/pending-elements-and-payloads/summary.json) · [Guide](../docs/GUIDE.md)
