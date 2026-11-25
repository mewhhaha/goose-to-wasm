# Release `v2026.4-5` Qualification & README Chart Provenance

Date: **2026-11-25**

## Qualification (`build/qualify-v2026.4-5/summary.json`, `122.7 s`, all stages exit 0)

- **Plain upstream C++ Goose check:** `build/native/goose check selfhost/main.goose --stdlib stdlib` — **exit 0**.
- **`bootstrap --verify`:** **`30.3 s`** (fixed-point + Clang 23 PGO `profile_used: true`).
- **`conformance` (`-O0`, `-O2`, gcc):** **`10,709 / 10,801`** (`99.15%`, `92` recorded gaps, **0 unexpected**).
- **`native-checks`:** `54 steps ok`.
- **`conformance-memory64`:** **`4,773 / 4,779`** (`99.87%`, `6` recorded gaps, **0 unexpected**, running on updated `host/rust` `goose-wasmtime`).
- **`unit-tests`:** all unit test suites passed (`58.3 s`), including multi-discard `_`, folded-global class-mode shrink regression tests (`tests/test_cli_outputs.py`), and `goose-wasmtime` / `goose-wtime` Blot2 host tests (`tests/test_wtime_host.py`).
- **`forced0` (`LIFE_CONCRETE_FRAMES = 0`) soundness audit:** `selfhost/main.goose --check` exit 0, `10,679 / 10,801` frontend conformance passing (**0 regressions** vs `v2026.4-4`).

## README Charts (`plot.py`)

The three consumer SVG charts in this directory are generated directly from pinned dated evidence by `python3 bench/results/2026-11-25/release-v2026.4-5/plot.py`:

- [`everyday_dev_loop.svg`](everyday_dev_loop.svg) — 8 everyday Goose examples (`-O2` Direct Wasm vs upstream C++ Goose `build -O2`), sourced from [`../release-v2026.4-4/results.json`](../release-v2026.4-4/results.json) (CPU 7, 5 alternating rounds; codegen and optimizer are unchanged in `v2026.4-5`).
- [`large_codebase_turnaround.svg`](large_codebase_turnaround.svg) — Self-hosting compiler (`selfhost/main.goose`, ~32k LOC, from [`../release-v2026.4-4/results.json`](../release-v2026.4-4/results.json)) alongside `mewhhaha/blot2` HEAD `98f277f2` (~135k LOC, from [`../blot2-head-98f277f2/metrics.json`](../blot2-head-98f277f2/metrics.json) and separate dated C reference builds documented in [`../blot2-head-98f277f2/README.md`](../blot2-head-98f277f2/README.md)).
- [`runtime_speed.svg`](runtime_speed.svg) — Compiled program runtime (`sorting`, `life`, `sudoku`, `sieve`, `maze`, `mandelbrot` 2048×2048), sourced from [`../release-v2026.4-4/results.json`](../release-v2026.4-4/results.json) (CPU 7, 5 alternating rounds, bit-exact output).
