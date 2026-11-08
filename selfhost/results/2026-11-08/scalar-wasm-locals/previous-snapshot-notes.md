# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 56 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `18fb5a123b4299622959748438fefdf4f19ff1edcefe8e9d24dcd7e138b76ade`. Compiler executable SHA-256: `b765aa67b7c00eb3761d9ae6969add66e6f5c2ecaefa24cabae017510abc2435`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 56 passed 7,687 of 7,787 rows; 100 failed. Against snapshot 55, 0 of 7,779 prior checks improved and none regressed. All 8 new source-authored checks passed. The 100 remaining failures comprise 6 invalid-program checks and 94 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,286/3,286 checks each in Wasmtime and V8; all 1,410 curated native controls also passed.

The lifetime checker indexes its containment memo by exact ordered key using bounded bucket heads. It retains the append ledger, answers and miss walk. Lifetime containment memo queries use an exact-key index; cached answers and containment traversal retain the existing contract. On the fixed snapshot 55 compiler workload, native C emission took 64.98 s with the prior compiler and 48.72 s with the index (CPU 64.63 vs 48.47 s). Peak-RSS medians were 602.9 and 602.8 MiB. Emitted C bytes match. These are two measured processes per compiler after one warmup, with alternating order on CPU 7. The common downstream C compilation took 30.05 s and is separate. The index reserves 128–131,072 logical head bytes per lifetime analysis and adds eight logical bytes per memo entry. Initialization and collision-chain lookup remain costs; the measured peak RSS records the full process.

Loop sequence temporaries live for the enclosing statement; binders enter loop scope afterward. Source-copy and escape rules remain in force. Wasm fixed aggregate value results snapshot the final channel rather than retain source aliases; references, slices and construction receivers keep identity. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 94 runtime contracts rejected during Goose compilation. All selected runtime checks that reached execution passed. No C++ oracle was executed. [Qualification details](results/2026-11-07/lifetime-containment-index/summary.json) · [Guide](../docs/GUIDE.md)
