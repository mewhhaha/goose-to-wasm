# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 57 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `b03232d61bed94dea5ffa30d408930993654ce8b5a4ad45acbaa160e0f89a3ae`. Canonical compiler executable SHA-256: `941742f8d9baf7adc22b592fd92708e0f40483116800688be56f2a93cf88d72c`. The separately identified public compiler used for performance measurements has SHA-256 `8b33754483aed2a04c8be11ac9c42a062f6c6720cbd58316d3c4b4f236803eb9`.


## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. Snapshot 57 passed 7,771 of 7,871 rows; the same 100 gaps remain from snapshot 56. All 84 new rows passed. The curated corpus passed 3,370 Wasm checks in each of Wasmtime and V8, plus 1,410 native controls. The remaining gaps are 6 accepted invalid programs and 94 runtime contracts rejected during Goose compilation; no selected runtime output mismatched. No C++ oracle was executed. [Qualification](results/2026-11-08/scalar-wasm-locals/summary.json)

Snapshot 57 omits the forwarding resolver only for emitted modules proven to use scalar and fixed scalar-array values. It also places eligible scalar parameters and simple declarations in typed Wasm locals, excluding captures, compound values and references. Frame offsets, reservations and debug checks remain intact. [Evidence and tradeoffs](results/2026-11-08/scalar-wasm-locals/README.md)

[Previous lifetime-checker measurements and contract limits](results/2026-11-08/scalar-wasm-locals/previous-snapshot-notes.md) · [Guide](../docs/GUIDE.md)
