# Continue here

Standing rules are in [AGENTS.md](AGENTS.md). All six items of the Batches 9–13 runtime-performance campaign are complete, qualified, measured, and pushed to `origin/main` (compiler at `949c5c0`, with all five reader suites and `bench/charts/*.svg` refreshed in the follow-up commit).

## Where it stands (2026-11-24)

- **Qualification gate (Batch 3: `l.alts` compaction, `opt_replace` exit retargeting, and default-2 GiB native Blot2 `6ad5fbb` build, all green):**
  - Plain upstream C++ Goose check (`build/native/goose check selfhost/main.goose --stdlib stdlib < /dev/null`): **exit 0**.
  - C bootstrap (`scripts/bootstrap.py --verify`): **fixed point reached** (`f187e0eb…`, executable `6ba2365f…`, `131.7 s`).
  - Default conformance: **10,697/10,801** (104 recorded gaps in [known-gaps.json](tests/conformance/known-gaps.json), 0 unexpected).
  - Memory64 conformance: **4,771/4,779** (8 recorded gaps in [known-gaps-memory64.json](tests/conformance/known-gaps-memory64.json), 0 unexpected).
  - Native runtime checks: **54/54** passed (`12.3 s`).
  - Unit tests: all passed (`57.6 s`), including the new `folded_inline_exits` regression (`true && inlined_fn()`, `false || inlined_fn()`, `if true { ... }`).
  - `forced0` (`LIFE_CONCRETE_FRAMES = 0`) conformance audit: **100% identical to Batch 1** (`126` failing rows on 10,801 frontend rows, **0 new failures**, `13/13` upstream sentinels rejected, `selfhost/main.goose` exit 0).
  - Blot2 memory & end-to-end `6ad5fbb` build under **default 2 GiB `--stack-reserve`**:
    - `cb1e9e15`: `87.62 s`, max RSS **`3.58 GiB`** (`-31.3%` vs `5.21 GiB`), peak `l.alts` `29.42M` (`794 MB`, `0` compactions, `0` `l.set_index`), exact 1 sound §5.2 diagnostic (`check/check.goose:3422:86`).
    - `6ad5fbb`: `238.16 s`, max RSS **`7.53 GiB`** (`-27.6%` vs `10.40 GiB` at 8 GiB), peak `l.alts` **`46.42M`** (`1.25 GB`, **`-64.0%`** vs `128.82M`, `l.set_index` `155.11M → 0`, combined **`-69.5%`**), exact 1 sound §5.2 diagnostic (`check/check.goose:3179:86`).
    - End-to-end native `6ad5fbb` release build (scratch copy with 1-line §5.2 `finishReflection` sort-buffer patch; `../blot2` untouched): `-O2 --header --expansion-node-limit 1000000` emit (`295.51 s`, `381.9 MB` C), `clang -O2` link with 6 `native/*.o` + `goose_runtime.o` + `-lm` (no `-rdynamic`, no `-ldl`) producing `22.08 MB` `blotc-goose` (`319.05 s`), compiling and verifying **9/9** grammar-compatible `benchmarks/idiomatic/*.blot` programs bit-exact against Rust in Node (the other 9 use `a[i] = v` store statements added later in Blot2 `de15d314`).
  - Own-source alternating 5-round timings vs Batch 2 (`51fbbebd… → 6ba2365f…`): `--check` `0.481 s → 0.458 s` (`-4.6%`), `--target c -O2` `0.798 s → 0.785 s` (`-1.6%`, byte-identical `23,251,828 B`), `--target wasm-direct -O2` `0.590 s → 0.571 s` (`-3.2%`, byte-identical `3,998,365 B`). [Evidence](bench/results/2026-11-24/blot2-alts-compaction-and-6ad5fbb/README.md)
- **Previous Batch 2 (2026-11-24, `29b30c2`):** C-host/library build interface (`--emit-runtime`, `--header`, `--shared`, `--standalone`, `goose_init`, `goose_exit`, direct C `extern fn` linking without `-rdynamic`/`-ldl`, reachable-export checking), 6 native codegen/checker fixes, and end-to-end native Blot2 `cb1e9e15` release build (`10.45 MB`, **18/18** idiomatic `.blot` benchmarks bit-exact vs Rust). [Evidence](bench/results/2026-11-24/blot2-chost-and-native-build/README.md)
- **Previous Batch 1 (2026-11-24, `5839a70`):** Lifetime checking precision & scalability fixes on both frozen Blot2 snapshots (`cb1e9e15` in `73.50 s` default 2 GiB, `6ad5fbb` in `215.51 s` with `--stack-reserve 8G`, 1 sound §5.2 diagnostic remaining; `forced0` conformance improved `78 → 75` fails, 0 new fails, 13/13 sentinels rejected). [Evidence](bench/results/2026-11-24/blot2-lifetime-fixes/README.md)
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
   - **Done (2026-11-24, Batch 1 `5839a70`):** Lifetime checking precision & scalability resolved on both frozen Blot2 snapshots (`cb1e9e15` in default 2 GiB, `6ad5fbb` with `--stack-reserve 8G`), leaving only the sound §5.2 rejection of `makeReflectionOrder(self_.reflections)` (upstream `d5ae5bb` `LoadSliceArgs` UAF bug). [Evidence](bench/results/2026-11-24/blot2-lifetime-fixes/README.md)
   - **Done (2026-11-24, Batch 2 `29b30c2`):** Implemented the C-host/library build interface (`--emit-runtime`, `--header`, `--shared`, `--standalone`, `goose_init`, `goose_exit`, direct C `extern fn` linking without `-rdynamic`/`-ldl`, reachable-export checking), fixed 6 native codegen/checker bugs surfaced by Blot2, built archived `cb1e9e15` into a working `10.45 MB` native `blotc-goose` release binary, and verified **18/18** idiomatic `.blot` benchmarks bit-exact against Rust. [Evidence](bench/results/2026-11-24/blot2-chost-and-native-build/README.md)
   - **Done (2026-11-24, Batch 3):** Canonicalized `LifeSet`s (removing `l.set_index`, `-620 MB`) and added memo-preserving inter-pass `l.alts` mark-and-compact GC (`life_reclaim_alts`), cutting peak `l.alts` on `6ad5fbb` by **-64.0%** (`128.82M → 46.42M`) so `6ad5fbb` checks and builds natively end-to-end inside the **default 2 GiB `--stack-reserve`** (`22.08 MB` `blotc-goose`, **9/9** grammar-compatible idiomatic `.blot` benchmarks bit-exact vs Rust); fixed `opt_replace` exit retargeting surfaced by `6ad5fbb` `-O2`. [Evidence](bench/results/2026-11-24/blot2-alts-compaction-and-6ad5fbb/README.md)
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
