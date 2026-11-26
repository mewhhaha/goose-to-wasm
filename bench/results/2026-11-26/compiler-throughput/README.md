# Compiler Throughput Campaign — Batch 1: Bounded Future-Span Caching & Reachable Future Global Marking (2026-11-26)

This study tracks compiler throughput improvements across frozen flat procedural code (`flat_multi_100k`, `flat_single_100k`), frozen own-source `selfhost/` (`f746c6e`, 47,395 LOC + stdlib), and frozen Blot2 `98f277f2` (78,954 LOC + read-only pinned Blot2 stdlib).

## Batch 1 — Fix 7× `selfhost` lifetime regression (`selfhost/checker_lifetimes.goose`)

### Root cause
Commit `90917c8` added local exit cutoffs (`future.last >= 0`, `l.future_exit`) in `life_block_future` for lifetime precision. Whenever an exit cutoff was active:
1. `life_body_span(p, l, start, last)` bypassed `l.node_body` and rebuilt a fresh `LifeBody` + sorted transitive-global closure on every query (**263,663 / 264,314** bounded span requests on `selfhost` and **23,035 / 23,470** on `Blot2` repeated an already-seen `(start, last)` pair).
2. `life_shrink_array` disabled bulk `life_mark_future_globals` and `shrink_clean`/`global_shrink_clean` caching whenever `l.future_exit.frame >= 0`, falling back to per-candidate `life_used_after` queries.

### Changes (`selfhost/checker_lifetimes.goose`)
1. Added an open-addressed `(start, last) -> body` cache (`span_slots`) inside `life_body_span`, reusing both the bounded `LifeBody` and its cached transitive globals (`body_trans_globals`).
2. Updated `life_mark_future_globals` to filter futures with `life_future_reachable`, key its cached mark vector by surviving `(future.node, future.last)` pairs, and query `life_body_span(p, l, fn_n, fn_last)`, enabling bulk marking for all non-capture global holders even when `l.future_exit.frame >= 0`.
3. Included reachable `(node, last, frame, loop_scope)` in `fhash` inside `life_shrink_array` so `shrink_clean` and `global_shrink_clean` remain active and exact under `future_exit`.

### Verification & Qualification
- **Plain upstream Goose reference check:** `build/native/goose check selfhost/main.goose --stdlib stdlib` — **exit 0**.
- **Structural fingerprints (`bench/results/2026-11-19/lifetime-store-delivery/tools/fingerprint.inc`):**
  - Default threshold (`LIFE_CONCRETE_FRAMES = 4096`): `selfhost` 8/8 checkpoints identical, `Blot2` 9/9 checkpoints identical.
  - Forced class (`LIFE_CONCRETE_FRAMES = 0`): `selfhost` 7/7 checkpoints identical, `Blot2` 7/7 checkpoints identical.
  - Pristine Blot2 `98f277f2` archive retains exact §5.2 rejection at `check/check.goose:5049`.
- **Full qualification (`build/qualify-batch1/summary.json`, `107.6 s`, all stages exit 0):**
  - `bootstrap --verify`: fixed point verified (`a9ffede7cfdc110b…`), executable `18869bc31780f6fb…` (unprofiled).
  - `conformance`: `10,797 / 10,801` (4 recorded gaps, 0 unexpected).
  - `conformance-memory64`: `4,773 / 4,779` (6 recorded gaps, 0 unexpected).
  - `native-checks`: `54 steps ok`.
  - `equivalence` vs frozen `v2026.4-3` (`3a900d10…`): **`10,061` compared, `0` differing** (`46.64 s → 33.42 s`).
  - `unit-tests`: all 22 modules passed.

### Paired CPU-7 Measurements (matched unprofiled Clang 23 `-O2`, 3 alternating rounds + 1 warmup)

- **Baseline (`v2026.4-3-nopgo`):** `9842a7998d8475ca…` (built from `bootstrap/seed.c.gz` with `clang -std=gnu11 -O2`)
- **Candidate (`batch1-nopgo`):** `18869bc31780f6fb…` (`build/qualify-batch1/bootstrap/bin/goosew`)
- **Raw JSON:** [`batch1_paired_nopgo_cpu7.json`](batch1_paired_nopgo_cpu7.json) (and separate PGO `v2026.4-3` baseline reference in [`baseline_v2026.4-3_cpu7.json`](baseline_v2026.4-3_cpu7.json))

| Workload | Baseline wall (ms) | Batch 1 wall (ms) | Wall speedup | `lifetime_ns` (ms) | Byte-identical |
|---|---:|---:|---:|---:|---|
| `selfhost_o0_wasm64` (47,395 LOC) | `3,831.0` | **`759.1`** | **5.05×** | `3,565.2 → 505.3` (**7.06×**) | yes (`3fcd1fce7b…`) |
| `selfhost_o2_wasm64` (47,395 LOC) | `3,837.3` | **`862.1`** | **4.45×** | `3,507.6 → 492.2` (**7.13×**) | yes (`fff47bea42…`) |
| `blot2_o0_wasm64` (78,954 LOC) | `3,265.0` | **`3,110.6`** | **1.05×** | `2,046.2 → 1,912.2` (**1.07×**) | yes (`2a39a0dd07…`) |
| `blot2_o2_wasm64` (78,954 LOC) | `4,240.1` | `4,217.6` | 1.01× | `2,191.8 → 2,122.7` | yes (`6a399d7b51…`) |

*(Separate dev PGO probe on CPU 7 with the existing Snapshot 72 profile measured `selfhost_o0_wasm64` at `733.8 ms` / `life = 489.1 ms` and `selfhost_o2_wasm64` at `813.5 ms` / `life = 495.1 ms`.)*

---

## Batch 2 — Single-Core Backend, Optimizer, Frontend & Lifetime Speedups

### Changes
1. **Direct Wasm backend (`selfhost/codegen.goose`, `selfhost/wasm.goose`):**
   - Replaced O(C²) `m.captures` scans in `cg_propagate_captures` and all capture consumers with per-function append-ordered linked rows (`capture_rows`, `capture_row_by_node`), an open-addressed `(function, symbol)` hash table (`capture_pair_slots`), and a one-time `cg_collect_capture_edges` edge vector with incremental cursor streaming.
   - Memoized `cg_has_relative` in bits 8–9 of `Type.codegen_memo` (`CG_MEMO_HAS_RELATIVE`, 4-state `0/1/2/3` cycle-safe iterative DFS with witness-ancestor marking and masked writes).
   - Streamlined `wb_reuse_locals` / `wb_reuse_body`: dropped unused `locals_at`, fused dead-write passes 2 & 2b, replaced linear control-frame scans with an O(1) `active_loops` stack, compacted undo entries in-place, skipped `old == mapped` wide rewrites, and emitted directly into `out`.
2. **Optimizer (`selfhost/optimizer.goose`, `selfhost/model.goose`, `selfhost/parser.goose`, `selfhost/checker_validation.goose`, `selfhost/driver.goose`):**
   - Replaced linear visited-list scans in `opt_separate_tree` / `opt_separate_call` with O(1) epoch stamps (`dependency_seen`, `dependency_epoch`) plus a watched `OptDepSummary` cache with structural invalidation hooks (crushing Blot2 `-O2` `optimize_ns` by **4.72×**).
   - Cached `Program.has_checked_checkfree` during `check_validate_program` and `Program.saw_inline_checkfree` during parsing to skip unused `-O0` call-count, index-variable, checkfree-scan, and inline-eligibility work.
3. **Checker (`selfhost/checker.goose`):**
   - Indexed `c.specializations` by original declaration node in insertion-ordered linked chains (`specialization_rows` / `next_spec`).
   - Added recursion-safe `choice_args` scratch and cursor traversal in `check_choose_call`, singleton shortcut in `check_function_shadowed`, and mark-on-enqueue in `check_validate_type_uses`.
4. **Lifetimes (`selfhost/checker_lifetimes.goose`):**
   - Included `last: i32` in `LifeRead` (shrinking it to 20 bytes) so bounded local-variable read queries hit `l.reads` (eliminating `selfhost`'s 24.5% `life_reads_miss` hotspot).
   - Memoized `life_bypasses_exit` per AST node (`bypass_memo`, eliminating Blot2's 7.5% validation leaf hotspot).
   - Added a sound whole-program pure-value fast path (`life_try_pure_fast_path`) for fixed-value, non-recursive, reference/global/capture/pool-free programs (preserving exact `provenance = -2` export and zero false accepts).

### Verification & Qualification
- **Plain upstream Goose reference check:** `build/native/goose check selfhost/main.goose --stdlib stdlib` — **exit 0**.
- **Structural fingerprints (`fingerprint.inc` vs Batch 1):**
  - Default (`4096`): `selfhost` 8/8 identical, `Blot2` 9/9 identical.
  - Forced class (`0`): `selfhost` 7/7 identical, `Blot2` 7/7 identical.
- **Full qualification (`build/qualify-batch2/summary.json`, `106.1 s`, all stages exit 0):**
  - `bootstrap --verify`: fixed point verified (`e2abdf09d4847efd…`), executable `23b526b3b7cfb7a1…` (unprofiled).
  - `conformance`: `10,797 / 10,801` (4 recorded gaps, 0 unexpected).
  - `conformance-memory64`: `4,773 / 4,779` (6 recorded gaps, 0 unexpected).
  - `native-checks`: `54 steps ok`.
  - `equivalence` vs Batch 1 (`18869bc3…`): **`10,061` compared, `0` differing**.
  - `unit-tests`: all 22 modules passed.

### Paired CPU-7 Measurements (matched unprofiled Clang 23 `-O2`, 3 alternating rounds + 1 warmup)

- **Baseline (`v2026.4-3-nopgo`):** `9842a7998d8475ca…`
- **Candidate (`batch2-nopgo`):** `23b526b3b7cfb7a1…` (`build/qualify-batch2/bootstrap/bin/goosew`)
- **Raw JSON:** [`batch2_paired_nopgo_cpu7.json`](batch2_paired_nopgo_cpu7.json)

| Workload | Baseline wall (ms) | Batch 2 wall (ms) | Wall speedup | Key stage deltas (ms) | Byte-identical |
|---|---:|---:|---:|---|---|
| `flat_multi_100k_o0` (98,749 LOC) | `279.3` | **`239.9`** | **1.17×** | `life 42.5 → 4.4`, `opt 38.6 → 30.8` | yes (`5d5090f074…`) |
| `flat_multi_100k_o2` (98,749 LOC) | `322.6` | **`277.8`** | **1.16×** | `life 42.6 → 4.4` | yes (`6227d67f32…`) |
| `flat_single_100k_o0` (98,604 LOC) | `271.8` | **`221.2`** | **1.23×** | `life 45.0 → 4.4`, `opt 35.7 → 29.1` | yes (`90ec860af5…`) |
| `selfhost_o0_wasm64` (47,395 LOC) | `4,315.3` | **`721.2`** | **5.98×** | `life 3,996.6 → 452.1` (**8.84×**) | yes (`3fcd1fce7b…`) |
| `selfhost_o2_wasm64` (47,395 LOC) | `4,035.3` | **`861.3`** | **4.68×** | `life 3,669.8 → 485.5` (**7.56×**), `opt 78.5 → 69.8` | yes (`fff47bea42…`) |
| `blot2_o0_wasm64` (78,954 LOC) | `3,701.4` | **`3,094.0`** | **1.20×** | `be 525.2 → 315.8` (**1.66×**), `opt 66.5 → 56.9`, `life 2,266 → 2,076` | yes (`2a39a0dd07…`) |
| `blot2_o2_wasm64` (78,954 LOC) | `4,017.2` | **`3,173.2`** | **1.27×** | `opt 767.3 → 162.4` (**4.72×**), `be 525.2 → 404.1` (**1.30×**) | yes (`6a399d7b51…`) |

