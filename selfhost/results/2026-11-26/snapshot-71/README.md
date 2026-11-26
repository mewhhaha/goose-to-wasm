# Snapshot 71 · 2026-11-26 (Joint GPT-6-Sol Audit Batches 1–3)

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the three-batch joint GPT-6-Sol audit fixes (`759802a`, `ee9c7f0`, and Batch 3 lifetime/checker fixes, replacing Snapshot 70 `ea29764a…`, 2026-11-25).

Changes from Snapshot 70 to Snapshot 71:
- **Batch 1 (`759802a`):** All 5 Direct Wasm hosts (`scripts/run_wasmtime.py`, `scripts/run_wasm.mjs`, `host/rust`, `host/wtime`, `host/wasmtime.cpp`), `native/storage.h`, `selfhost/{codegen_c,driver,sources}.goose`, `selfhost/bootstrap.py`, `scripts/bootstrap.py`, `stdlib/std.goose` (host bounds/UTF-8/NUL/stdin parity, `format_float` exact precision/NaN/Inf/-0.0, driver clobber guards & non-`.c` `--run`, native C runtime overflow/cleanup fixes).
- **Batch 2 (`ee9c7f0`):** All 13 confirmed Direct Wasm bugs in `selfhost/codegen.goose` (enum payload side-metadata guard, forwarding bucket-table undo journal at `-O0`/`-O2`, varint relative-reference arrays, `A_LIMITED` array adaptation preserving image start, per-slot `alloc_slice` field defaults, reusable pool stack-slot zeroing, diverging-argument call evaluation + `cg_address` temporary materialization).
- **Batch 3 (`selfhost/checker.goose`, `selfhost/checker_lifetimes.goose`, `tests/conformance/known-gaps.json`, `tests/test_cli_outputs.py`):**
  - `N_DEFER` LIFO block-exit lifetime stack (`LifeDefer`, `LifeDeferTarget`, `life_run_defers`, block/return/break/continue unwinding and active-defer futures).
  - Post-pin upstream HEAD `errors_tc` checks: reject relative references inside `from_bytes<T[>..<]>` (`serialize_grow_shrink_refs`), verify `from_bytes` element index types against global initialization order (`global_before_init_from_bytes_index`), and treat non-exact by-value holder parameters as inexact depth bounds inside callee bodies while keeping caller-side exactness (`holder_param_inexact_views`, `holder_param_inexact_views_copy`).

| Item | Identity |
| --- | --- |
| Seed C | `e851b5386423997d87748ca4793bff6c6f2562d95dd2709f3aa29a1eb26dd631` (`26,134,027 B`, stage 1 `2056004c…`, stage 2 = stage 3 = `e851b538…` from Snapshot 70's seed `ea29764a…`) |
| Compressed seed | `seed.c.gz` (`4,356,984 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `d88c409108c9d128697777a4fe1ac3d2f7f82d6ff5da36136d2058f6aeacdf69` (`777,840 B`) |
| Executable with profile | `07833ca76404253664f1a8a187b8165173c63b3c17f648b1f57057eaefe4992d` |
| Executable without profile | `874cf431ad1e6106495244a0cac891b0315b74b15a0eb8c4f3104c52ad781bd0` |

**Profile.** Trained with the `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. None of the timed benchmark programs or Blot2 snapshots was used in training.

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`28.8 s`) and with explicit options (`28.8 s`). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `07833ca7…` (`goose-to-wasm v2026.4-2 (Goose v2026.4)`). [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-batch3 --jobs 8` passed all stages in `131.2 s` using the profiled executable `07833ca7…` (`bootstrap` `29.5 s`, `profile_used: true`, `10,797/10,801` conformance with 0 unexpected failures, `4,773/4,779` memory64, `54/54` native checks, all 21 unit test suites exit 0, `tests.test_native_wasmtime` `16/16`, plain upstream C++ Goose check exit 0). [Summary](qualification.json)
