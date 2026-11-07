# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 52 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `11435d57daa506c1e9a161b4c20e9288d47feeb9730e7538bf792bcecc96789f`. Compiler executable SHA-256: `7a2ec7fe06f0c46b79ee298de14c4b207270b2408a883138939258982d84a391`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 52 passed 7,397 of 7,503 rows; 106 failed. Against snapshot 51, 2 of 7,435 shared checks improved and none regressed. All 68 new source-authored checks passed. The 106 remaining failures comprise 6 invalid-program checks and 100 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,144/3,144 checks each in Wasmtime and V8; all 1,268 curated native controls also passed.

Concrete generic arguments constrain types before flexible array and fill literals, including nested and control-flow leaves. Floating literal arrays use the existing float-before-integer order. Runtime evaluation order and final fitting and ranking are unchanged; named-literal parameter authority remains separate. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 100 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. No C++ oracle was executed. [Qualification details](results/2026-11-07/literal-array-inference/summary.json) · [Guide](../docs/GUIDE.md)
