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
