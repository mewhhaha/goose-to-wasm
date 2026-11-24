# Continue here

Standing rules are in [AGENTS.md](AGENTS.md). All six items of the Batches 9–13 runtime-performance campaign are complete, qualified, measured, and pushed to `origin/main` (compiler at `949c5c0`, with all five reader suites and `bench/charts/*.svg` refreshed in the follow-up commit).

## Where it stands (2026-11-24)

- **Qualification gate (Blot2 lifetime precision & scalability batch, all green):**
  - Plain upstream C++ Goose check (`build/native/goose check selfhost/main.goose --stdlib stdlib < /dev/null`): **exit 0**.
  - C bootstrap (`scripts/bootstrap.py --verify`): **fixed point reached** (`0ed55897…`, executable `7a08e2ee…`).
  - Default conformance: **10,697/10,801** (104 recorded gaps in [known-gaps.json](tests/conformance/known-gaps.json), 0 unexpected).
  - Memory64 conformance: **4,771/4,779** (8 recorded gaps in [known-gaps-memory64.json](tests/conformance/known-gaps-memory64.json), 0 unexpected).
  - Native runtime checks: **54/54** passed.
  - Unit tests: all passed (`54.9 s`), including 11 new `ClassLifetimeChecks` regression and negative-control cases in [tests/test_cli_outputs.py](tests/test_cli_outputs.py).
  - `forced0` (`LIFE_CONCRETE_FRAMES = 0`) conformance audit: **75 fails vs 78 at `92125b6`** (**0 new fails**, **3 upstream `forced0` tests fixed**: `shrink_slice_ref_explicit_callee`, `shrink_slice_ref_loaded`, `growshrink_unrelated_refs`), **13/13** upstream lifetime sentinels rejected.
  - Blot2 snapshots: `cb1e9e15` (`73.50 s`, default 2 GiB `--stack-reserve`) and `6ad5fbb` (`215.51 s`, `--stack-reserve 8G`) both complete full lifetime discovery and validation with **1** remaining diagnostic (`makeReflectionOrder(self_.reflections)`, a sound §5.2 rejection where upstream `d5ae5bb` has a `LoadSliceArgs` UAF false-accept bug). Own-source `--check` improved **−20.1%** (`0.412 s → 0.329 s` 8-unit dev; `0.324 s` qualified release). [Evidence](bench/results/2026-11-24/blot2-lifetime-fixes/README.md)
- **Completed Batches 9–13 on `origin/main`:**
  - **Batch 9 (`f990ed2`):** Expanded intra-procedural BCE and direct Wasm/C `N_INDEX` lowering. [Evidence](bench/results/2026-11-23/bce-and-direct-indexing/README.md)
  - **Batch 10 (`4da2994`):** Loop-invariant Wasm array header hoisting (LICM). [Evidence](bench/results/2026-11-23/wasm-loop-header-hoisting/README.md)
  - **Batch 11 (`fc96a03`):** Small-struct SROA, direct `.push(Record)` / `arr[i] = Record` lowering, and Wasm multi-value returns. [Evidence](bench/results/2026-11-23/wasm-sroa-multivalue/README.md)
  - **Batch 12 (`28dec22`):** Closed **86% (Clang)** and **93% (GCC)** of the native C codegen gap to upstream C++ Goose (`native/storage.h`, `selfhost/codegen_c_storage.goose`, `selfhost/codegen_c.goose`); emitted C shrank **−45.9%** (`38.85 MB → 21.01 MB`), cutting 4-core Clang self-host build time from **20.05 s → 9.72 s**. [Evidence](bench/results/2026-11-23/native-c-codegen-gap/README.md)
  - **Batch 13 (`949c5c0` + reader refresh):** Stack-based `local.set; local.get` → `local.tee` / drop folding in `wb_reuse_locals`, `cg_may_region` + `cg_may_print` + zero-acquisition dead-mark stripping (`g3` **−97.4% / −95.5%**, `g0` **−92.9% / −85.6%**), cold per-message abort outlining (**21,449** sites), read-only `../wtime` (`wtime-aot` `6ed7ed3c`) evaluation, and full refresh of all five reader benchmark suites + `bench/charts/*.svg`. [Evidence](bench/results/2026-11-23/wasm-peephole-wtime-aot-and-refresh/README.md)
- **Current headline performance (CPU 7, 7 alternating rounds, pinned `949c5c0`):**
  - Release sizes: `direct.wasm` **2.91 MB** (gzip 0.80 MB, `.cwasm` 5.40 MB), `balanced.wasm` **2.48 MB** (gzip 0.73 MB, `.cwasm` 4.97 MB), `size.wasm` **2.26 MB** (gzip 0.64 MB), portable memory64 `compiler.wasm` **4.04 MB**.
  - Self-compile `selfhost/main.goose` → memory64 Wasm (`4,043,778 B`): cached Wasmtime balanced **0.955 s** (`7.13 B` instr; `size` **0.930 s**), `wtime-aot` 32-bit safe Rust **0.825 s** (`6.89 B`, IPC 2.116), native Clang `-O2` **0.650 s** (`4.25 B`), native GCC `-O2` **0.637 s** (`4.10 B`) — vs plain upstream C++ Goose **4.62 s** `check` / **4.93 s** emit C (**5.16×–7.74× faster**).
  - Frozen `9a6040a` → memory64 Wasm (`5,000,455 B`): cached Wasmtime balanced **0.703 s** (cold **2.54 s**; `size` **0.692 s**), `wtime-aot` 32-bit **0.606 s**, native Clang **0.481 s**, native GCC **0.475 s**.
  - Runtime kernels: `examples/sorting.goose` **75.6 ms** Wasmtime / **68.2 ms** `wtime-aot` / **50.8 ms** Clang / **46.0 ms** GCC; `owner_kernel` **13.4 ms** Wasmtime / **5.22 ms** `wtime-aot` (AVX2) / **9.16 ms** Clang / **10.55 ms** GCC; `sroa_kernel` **85.4 ms** Wasmtime / **67.9 ms** `wtime-aot` / **51.9 ms** Clang / **50.7 ms** GCC.
- **Seed note:** Checked-in C seed is still snapshot 63 (`selfhost/results/2026-11-14/snapshot-63/README.md`). Bootstrapping from snapshot 63 works and reaches fixed point cleanly; updating the checked-in seed to post-Batch-12/13 C (46% smaller, ~2× faster to compile) is an optional follow-up following the snapshot 63 protocol.

## Next priorities

1. **Blot2 compatibility (standing primary compatibility frontier — [docs/FEATURES.md#blot2-compatibility](docs/FEATURES.md#blot2-compatibility)).**
   - **Done (2026-11-24):** Lifetime checking precision & scalability resolved on both frozen Blot2 snapshots (`cb1e9e15` in default 2 GiB, `6ad5fbb` with `--stack-reserve 8G`), leaving only the sound §5.2 rejection of `makeReflectionOrder(self_.reflections)` (upstream `d5ae5bb` `LoadSliceArgs` UAF bug). [Evidence](bench/results/2026-11-24/blot2-lifetime-fixes/README.md)
   - **Next (Batch 2):** Implement the C-host/library build interface needed to link Blot2 natively (`--emit-runtime`, `--header`, `goose_init`, `goose_exit`, `--shared`, and reachable-export checking without `--library` checking unreachable code), then build and run archived Blot2 natively against `native/*.c` (keeping `../blot2` read-only).
   - Keep sibling checkouts (`../blot2`, `../wtime`, upstream Goose) strictly read-only and copy/archive pinned commits into `build/` before testing.
   - Keep the 4,096-frame class-keyed threshold until the remaining forced-class upstream disagreements are resolved.
2. **Next runtime and compiler speed opportunities (after or alongside compatibility):**
   - **Refresh checked-in C seed & PGO profile:** Regenerate the checked-in seed + Clang IR profile from post-Batch-13 C (21 MB vs 39 MB) using the [snapshot 63 protocol](selfhost/results/2026-11-14/snapshot-63/README.md) to speed up fresh `scripts/bootstrap.py --verify` runs.
   - **Close remaining Wasmtime vs native gap (`0.955 s` vs `0.637 s` on own source):**
     - Lifetime phase is still the largest slice (**461.5 ms** Wasmtime vs **408.6 ms** `wtime-aot` vs **301.8 ms** native GCC). Profile Cranelift codegen on hot lifetime functions (`life_eval_node`, `life_readback`, `life_effect_far`, `life_call`) to eliminate remaining memory-frame/register-spill overhead.
     - Investigate the Cranelift 50.0.1 register-allocation spill observed on `sroa_kernel` (Batch 13 cut retired instructions `-6.3%` to `0.660 B`, but Cranelift reloaded the array header slot inside the shortened loop body; `wtime-aot` stayed at `67.9 ms`).
     - Investigate why 64-bit Wasm (`wtime-aot` `1.271 s`, Wasmtime bundled 64-bit `1.36 s`) still trails 32-bit (`0.825 s` / `0.955 s`) by ~40–50% (v128 slice ops, i64 addressing, bounds-check width).
   - **Native C emitter follow-ups:** Close the last ~7–14% instruction gap to upstream C++ Goose C output (`4.10 B` vs `3.32 B` on GCC / `4.25 B` vs `3.45 B` on Clang) — check remaining bounds checks (`4,183/14,080` BCE vs upstream), small-helper inlining, and `g_push_slot` slow-path outlining.
   - **Upstream feature gaps:** Track and burn down remaining rows in [docs/FEATURES.md](docs/FEATURES.md) and [tests/conformance/known-gaps.json](tests/conformance/known-gaps.json).

## Key commands

Always use `.venv/bin/python` and pass `< /dev/null` to compiler/host/test commands.

```sh
# Upstream C++ Goose compatibility check (must stay exit 0)
build/native/goose check selfhost/main.goose --stdlib stdlib < /dev/null

# Fast local development bootstrap (8 parallel C units)
.venv/bin/python scripts/bootstrap.py --build-dir build/dev --jobs 8 \
  --cache-dir build/qualify-cache/bootstrap < /dev/null

# Full qualification run (bootstrap --verify, conformance, memory64, native checks, unit tests)
.venv/bin/python scripts/qualify.py --output-dir build/qualify-next --jobs 8 < /dev/null

# Rebuild native Wasmtime hosts if system clang++ updated
.venv/bin/python scripts/build_wasmtime_host.py < /dev/null
.venv/bin/python scripts/build_wasmtime_host.py --runtime-only < /dev/null

# Targeted backend/codegen unit tests
.venv/bin/python -m unittest \
  tests/test_native_units.py \
  tests/test_native_c_codegen.py \
  tests/test_wasm_sroa_multivalue.py \
  tests/test_wasm_licm.py \
  tests/test_bce_and_direct_index.py \
  tests/test_wasm_peephole.py < /dev/null
```
