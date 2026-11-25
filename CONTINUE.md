# Continue here

Standing rules are in [AGENTS.md](AGENTS.md). All six items of the Batches 9–13 runtime-performance campaign are complete, qualified, measured, and pushed to `origin/main` (compiler at `949c5c0`, with all five reader suites and `bench/charts/*.svg` refreshed in the follow-up commit).

## Where it stands (2026-11-25)

- **Direct Wasm `reusable[]` slice pools, flat `from_bytes`, O(1) forwarding resolver & Blot2 Wasm64 end-to-end (post-`v2026.4-3`, qualified):**
  - Implemented Direct Wasm `reusable[]` slice pools (`alloc_slice`, `realloc_slice`, `free_slice`, builtins `33..35`) in `selfhost/codegen.goose` for both `wasm32` and `--wasm-memory64` using an O(1) open-addressed pool-state hash table and upstream's 512-byte B+ max-augmented span tree (`LEAF=31`, `FAN=20`, `DEPTH=24`), matching upstream §5.4 placement/coalescing/regrowth/error semantics (`6/6` `upstream/runtime/slice_pool*` + `pool-rebind/slice-freelist.goose` + `tests/test_slice_pool_backends.py` `DirectWasmReusableSlicePools` pass).
  - Fixed diverging control flow in `cg_to` targeting `TY_REF`, implemented flat fixed-size `from_bytes<T[>..]>` verification in Direct Wasm (canonical ULEB length prefix, bool, fixed-mode enum tag & payload checks, both region and non-region modes), and upgraded `m.resolver` + `m.forward_helper` from an O(N) linked list to a lazily allocated O(1) 4 KiB page-bucketed table (zero bytes changed for region-enabled modules).
  - Full qualification (`build/qualify-wasm-slice-pool/summary.json`, `274.3 s`, upstream C++ Goose check exit 0, fixed-point C `82b042df…`, executable `5ea221b7…`, `10,697/10,801` conformance, `4,771/4,779` memory64, `54/54` native checks, `20/20` unit test suites, self-host Wasm64 byte-identical `c24eeea6…`, `9,997/10,061` byte-identical equivalence vs `v2026.4-3` with all `64` diffs confined to `m.resolver` / `slice-freelist` Wasm binaries).
  - **Blot2 `cb1e9e15` compiled & executed as Direct Wasm64:** Compiles in `9.1 s` to a validated `43 MB` `--wasm-memory64` module (`--reachable-program --wasm-max-pages 4096 -O2`, 85 imports: 10 `goose.*`, 19 math, 56 `env.blot_*`) and compiles **18/18** `benchmarks/idiomatic/*.blot` programs inside Wasmtime (`175–369 ms` each) to **18/18 byte-identical `.wasm` binaries** matching native `blotc-goose`.
- **Release `v2026.4-3` (qualified, 7-round class-keyed lifetime checker algorithmic redesign):**
  - Version string `goose-to-wasm v2026.4-3 (Goose v2026.4)` in `selfhost/driver.goose`, full qualification (`build/qualify-v2026.4-3/summary.json`, `269.2 s`, all stages exit 0: upstream C++ Goose check exit 0, fixed-point C `00ffd1ea…`, executable `209831db…`, `10,697/10,801` default conformance, `4,771/4,779` memory64, `54/54` native checks, `10,061/10,061` byte-identical equivalence vs `v2026.4-2`, `20/20` unit test modules).
  - Forced-class (`LIFE_CONCRETE_FRAMES = 0`) soundness audit: `10,675/10,801` passed (`126` failing rows, `0` newly failing / `0` newly passing vs baseline), `selfhost/main.goose --check` exit 0.
  - Head-to-head CPU-7 benchmarks vs `v2026.4-2` and plain upstream C++ Goose (`d5ae5bb`):
    - `selfhost/main.goose` (~30k LOC): `--check` **`0.297 s`** (**−17.0%** vs `v2`'s `0.358 s`, **14.0× faster** than upstream's `4.139 s`), emit Wasm64 `-O2` **`0.482 s`** (**9.2× faster**), emit C `-O2` **`0.506 s`** (**8.8× faster**); portable Wasm64 in Wasmtime checks in **`0.886 s`** (**4.7×**) and emits bit-identical Wasm64 in **`1.284 s`** (**3.5×**).
    - 8 real Goose examples: Direct Wasm `-O2` builds in `2.1–7.7 ms` vs upstream `goose build -O2` `53.5–179.3 ms` (**22×–29× faster**).
    - Frozen Blot2 default-2 GiB paired CPU-7 checks (3 rounds each): `cb1e9e15` **`6.52 s` / `2.06 GiB` RSS** (**2.96× faster**, **−41.5% RSS** vs `v2`'s `19.27 s` / `3.53 GiB`), `6ad5fbb` **`16.98 s` / `4.80 GiB` RSS** (**4.32× faster**, **−37.4% RSS** vs `v2`'s `73.43 s` / `7.66 GiB`). [Release `v2026.4-3` evidence & charts](bench/results/2026-11-25/release-v2026.4-3/README.md) · [Algorithmic redesign report](bench/results/2026-11-25/blot2-lifetime-algo/README.md)
- **Release `v2026.4-2` (qualified, C/Wasm/lifetime speedups, exquisite diagnostics, Wasm `env.*` host-import docs & tests):**
  - Version string `goose-to-wasm v2026.4-2 (Goose v2026.4)` in `selfhost/driver.goose`, full qualification (`build/qualify-v2026.4-2/summary.json`, `262.4 s`, all stages exit 0: fixed-point C `a0ec56f6…`, executable `93731c80…`, `10,697/10,801` default conformance, `5,926/6,022` split-unit native, `4,771/4,779` memory64, `54/54` native checks, `20/20` unit test modules including `tests.test_diagnostics`).
  - Forced-class (`LIFE_CONCRETE_FRAMES = 0`) soundness audit: exact `126` failing rows on `10,801` (`0` new failures), `13/13` upstream lifetime sentinels rejected, `selfhost/main.goose` exit 0.
  - Head-to-head CPU-7 benchmarks vs `v2026.4-1` and plain upstream C++ Goose (`d5ae5bb`):
    - `selfhost/main.goose` (~30k LOC): `--target c -O2` `0.691 s → 0.528 s` (**−23.6%** vs `v1`, **8.5× faster** than upstream's `4.468 s`; C backend alone `332.8 ms → 151.5 ms`, **−54.5% / 2.20×**), emit Wasm64 `0.534 s → 0.519 s` (**8.6× faster** than upstream), `--check` `0.390 s` (**10.5× faster** than upstream's `4.082 s`; Wasmtime Wasm64 `1.007 s`, **4.1×**).
    - 8 real Goose examples: Direct Wasm `-O2` builds in `1.9–8.4 ms` vs upstream `goose build -O2` `58.6–198.9 ms` (**24×–32× faster**).
    - Frozen Blot2 default-2 GiB paired CPU-7 checks: `cb1e9e15` **`19.21 s`** (`−3.0%` vs `v1`'s `19.81 s`, `4.4×` vs Batch 3), `6ad5fbb` **`73.63 s`** / `7.41 GiB` RSS (**`−7.2%`**, **`−280 MiB` RSS** vs `v1`'s `79.38 s` / `7.69 GiB`, `3.2×` vs Batch 3). [Release `v2026.4-2` evidence & charts](bench/results/2026-11-24/release-v2026.4-2/README.md)
  - Diagnostics & host imports: source-line snippets + `^~~~` carets, duplicate/cascade suppression, expected-vs-got types + `help:`, overload candidate signatures with `file:line`, Damerau-Levenshtein typo suggestions, lifetime call stacks + invalidated variable locations, and actionable Wasm `env.<name>` host-import ABI diagnostics + README documentation.
- **Release `v2026.4-1` (qualified, consumer README & benchmarks vs upstream C++ Goose):**
  - Version string `goose-to-wasm v2026.4-1 (Goose v2026.4)` in `selfhost/driver.goose`, full qualification (`build/qualify-v2026.4-1/summary.json`, `282.6 s`, all stages exit 0: fixed-point C `dbfecfe0…`, executable `139b06db…`, `10,697/10,801` default conformance, `4,771/4,779` memory64, `54/54` native checks, 19/19 unit tests).
  - Head-to-head CPU-7 benchmarks vs plain upstream C++ Goose (`d5ae5bb`):
    - `selfhost/main.goose` (~30k LOC): `--check` `0.363 s` vs `3.615 s` (**10.0× faster**; Wasm64-in-Wasmtime `1.090 s`, **3.3×**), emit Wasm64 `0.496 s` / emit C `0.731 s` vs upstream emit C `4.058 s` (**8.2× / 5.6× faster**).
    - 8 real Goose examples: Direct Wasm `-O2` builds in `2.1–6.9 ms` vs upstream `goose build -O2` `60.4–174.2 ms` (**24×–31× faster**).
    - Runtime speed: Native `-O2` matches upstream C++ Goose within ~1–3% (`sorting` `35.38 ms` vs `35.48 ms`, `mandelbrot` `2.419 s` vs `2.355 s`); Wasmtime hits `46.50 ms` on `sorting` and `1.974 s` on `mandelbrot`.
    - Frozen Blot2 default-2 GiB checks: `cb1e9e15` **`22.79 s`** (`3.34 GiB`), `6ad5fbb` **`81.87 s`** (`5.94 GiB`) — vs plain upstream timing out past `180 s` (`--header`) / `240 s` (`check`). [Release evidence & charts](bench/results/2026-11-24/release-v2026.4-1/README.md)
- **Previous Batch 4 (2026-11-24, `9e1eec0`):** Five profile-driven rounds of class-keyed lifetime checker speedups in `selfhost/checker_lifetimes.goose`, cutting default-2 GiB checks **3.59×** on `cb1e9e15` (`84.15 s → 23.42 s`, `-118 MiB` RSS) and **2.70×** on `6ad5fbb` (`238.16 s → 88.28 s`), with identical `forced0` conformance (`126` fails, 0 new, `13/13` sentinels). [Evidence](bench/results/2026-11-24/blot2-lifetime-speed/README.md)
- **Previous Batch 3 (2026-11-24, `2f97b6d`):** `l.alts` canonicalization & inter-pass mark-and-compact GC (`life_reclaim_alts`), `opt_replace` exit retargeting fix, and default-2 GiB native Blot2 `6ad5fbb` release build (`22.08 MB`, **9/9** grammar-compatible idiomatic `.blot` benchmarks bit-exact vs Rust). [Evidence](bench/results/2026-11-24/blot2-alts-compaction-and-6ad5fbb/README.md)
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
   - **Done (2026-11-24, Batch 3 `2f97b6d`):** Canonicalized `LifeSet`s (removing `l.set_index`, `-620 MB`) and added memo-preserving inter-pass `l.alts` mark-and-compact GC (`life_reclaim_alts`), cutting peak `l.alts` on `6ad5fbb` by **-64.0%** (`128.82M → 46.42M`) so `6ad5fbb` checks and builds natively end-to-end inside the **default 2 GiB `--stack-reserve`** (`22.08 MB` `blotc-goose`, **9/9** grammar-compatible idiomatic `.blot` benchmarks bit-exact vs Rust); fixed `opt_replace` exit retargeting surfaced by `6ad5fbb` `-O2`. [Evidence](bench/results/2026-11-24/blot2-alts-compaction-and-6ad5fbb/README.md)
   - **Done (2026-11-24, Batch 4):** Five profile-driven rounds of sound lifetime checker speedups (`LifeSet.flags` global/class bits, `LifeCallSig` interning, `held_epoch` memoization, SCC-safe discovery clean-frame skipping with per-root global dependency tracking, compact `LifeAlt`/`LifeAssume`/`LifeMapped`/`LifeJoin` structs, zero-copy `life_build_end`, and single-probe assumption lookup), cutting default-2 GiB checks **3.59×** on `cb1e9e15` (`84.15 s → 23.42 s`, `-118 MiB` RSS), **2.70×** on `6ad5fbb` (`238.16 s → 88.28 s`), and **−8.3%** on own-source `--check` (`0.418 s → 0.383 s`), with identical `forced0` conformance (`126` fails, 0 new, `13/13` sentinels). [Evidence](bench/results/2026-11-24/blot2-lifetime-speed/README.md)
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
