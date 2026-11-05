# Goose in Goose

The compiler is written entirely in Goose, including the frontend, optimization, native C and direct Wasm emission, and command-line driver. The [IR contract](IR.md) describes the stage interfaces.

## Bootstrap

From the repository root, with Python 3 and a native C compiler (Clang by default):

```sh
python3 scripts/bootstrap.py --verify
```

Bootstrap builds the checked-in C seed, uses it to compile the current Goose compiler to C, and builds that compiler. Verification compares consecutive generated C outputs. The installed compiler and standard library are in `build/bin`; `build/bootstrap/report.json` records inputs and commands. Use `--cc` to select a C compiler. Node is needed to run Wasm output.

Snapshot 42 passed C-only fixed-point verification; its final two generated C outputs match. Generated C SHA-256: `6916e27a944d67c6d07a1c39b20382f6209d134ff943c8ed1863de62074f9081`. Compiler executable SHA-256: `6e82bc259a95ac02f017eb78804dc3f9b8be5a758faedcf59bf35940967d3adb`.

## Contracts

```sh
python3 tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite checks frozen sources, outputs, exit statuses and failure phases without a reference compiler. **Conformance is partial:** snapshot 42 passed 5,121 of 5,300 rows; 179 failed. Against snapshot 41, 25 of 5,118 shared checks improved and none regressed. All 182 new source-authored checks passed. The 179 remaining failures comprise 33 invalid-program checks and 146 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 2,090/2,090 checks each in Wasmtime and V8; all 119 curated native controls also passed. No C++ oracle was executed.

Snapshot 42 decodes packed match varints while preserving their physical place and constructs match results at the actual receiver. Rendering handles explicitly padded variant records and distinguishes slice payload constness from readonly binding slots. Lifetime checking handles private and caller-bound views and commits fresh declarations with memoized immutable bound sets. Assignment analysis separates normal returns from nonlocal exits. The remaining failures are 33 accepted invalid programs and 146 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification details](results/2026-11-05/match-render-and-views/summary.json) · [Guide](../docs/GUIDE.md)
