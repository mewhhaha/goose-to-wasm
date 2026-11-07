# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 53 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `a25439f2b0d546555ace11d683b143e23d313394e8fcb160982d7a7e9a0e01b6`. Compiler executable SHA-256: `c7c51ab1fee6c71f84d3b5fb6cbdde2aa6ceb8659ab203c1e52c93ab7d6cc1ad`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 53 passed 7,493 of 7,595 rows; 102 failed. Against snapshot 52, 4 of 7,503 shared checks improved and none regressed. All 92 new source-authored checks passed. The 102 remaining failures comprise 6 invalid-program checks and 96 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,190/3,190 checks each in Wasmtime and V8; all 1,314 curated native controls also passed.

Loop sequence temporaries live for the enclosing statement; binders enter loop scope afterward. Source-copy and escape rules remain in force. Wasm fixed aggregate value results snapshot the final channel rather than retain source aliases; references, slices and construction receivers keep identity. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 96 runtime contracts rejected during Goose compilation. All selected runtime checks that reached execution passed. A separate 10,000-iteration temporary-array stress traps under a two-page Wasmtime limit in both snapshot 52’s by-value variant and snapshot 53. This does not establish reclamation or equal allocation volume. No C++ oracle was executed. [Qualification details](results/2026-11-07/temporary-values-and-copies/summary.json) · [Guide](../docs/GUIDE.md)
