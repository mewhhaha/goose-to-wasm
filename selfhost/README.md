# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 55 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `eb9ba3b7cb5a8be6c29583c32589eb329d1f95283d4debf16cb8341050096499`. Compiler executable SHA-256: `195c1d74e4b6f79829c93be239d3a3c7cf4606fcd8feb13ba14b15a397ce2a26`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 55 passed 7,679 of 7,779 rows; 100 failed. Against snapshot 54, 2 of 7,711 prior checks improved and none regressed. All 68 new source-authored checks passed. The 100 remaining failures comprise 6 invalid-program checks and 94 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,282/3,282 checks each in Wasmtime and V8; all 1,406 curated native controls also passed.

The checker compares raw constant slice bounds for reversed order only when neither endpoint uses `^`. Both backends normalize from-end bounds as `len - k` and retain runtime range checks. From-end slices now use the existing normalized runtime range checks. The complete original parser_all program passes native C at O0/O2; whole-program Wasm emission remains refused by the existing thread ABI boundary, with no partial-source gain claimed.

Loop sequence temporaries live for the enclosing statement; binders enter loop scope afterward. Source-copy and escape rules remain in force. Wasm fixed aggregate value results snapshot the final channel rather than retain source aliases; references, slices and construction receivers keep identity. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 94 runtime contracts rejected during Goose compilation. All selected runtime checks that reached execution passed. No C++ oracle was executed. [Qualification details](results/2026-11-07/from-end-slice-bounds/summary.json) · [Guide](../docs/GUIDE.md)
