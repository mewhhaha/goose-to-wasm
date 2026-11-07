# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 54 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `46792d91fb3a7da1d53ce009599a405482c3ceff4df47e74bdc6ff509b5b63f0`. Compiler executable SHA-256: `cd387f7a708d7f2f6bd2e934204da4da9d9466058daab37da08e125d284e7c4f`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 54 passed 7,609 of 7,711 rows; 102 failed. All 7,595 prior checks retained their outcomes. All 116 new source-authored checks passed; these include bounded-memory contracts rather than recovered original-suite failures. The 102 remaining failures comprise 6 invalid-program checks and 96 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,248/3,248 checks each in Wasmtime and V8; all 1,372 curated native controls also passed.

The Wasm backend detects owned call results, constructors and function outputs when selecting the existing admitted region runtime, and restores the transient region count after each global declaration. This does not widen representation admission.

Loop sequence temporaries live for the enclosing statement; binders enter loop scope afterward. Source-copy and escape rules remain in force. Wasm fixed aggregate value results snapshot the final channel rather than retain source aliases; references, slices and construction receivers keep identity. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 96 runtime contracts rejected during Goose compilation. All selected runtime checks that reached execution passed. Repeated 10,000-iteration temporary workloads, including str and to_bytes, now fit the same two-page Wasm limit. Thirty-two scalar startup initializers reuse one region instead of 33; an 8,192-byte main temporary then fits without increasing the limit. The guards also preserve live global owners and views and still reject a live value larger than the limit. Unsupported representations still use fallback paths that may retain temporaries. Across 41 changed small modules in the targeted cohort, emitted size was 0.831–1.815 times baseline and median compile CPU was 1.076 times baseline. The 13 byte-identical controls had a median compile CPU ratio of 0.986. These are targeted costs of the final candidate, separate from the ten-example process comparison. No C++ oracle was executed. [Qualification details](results/2026-11-07/temporary-region-retirement/summary.json) · [Guide](../docs/GUIDE.md)
