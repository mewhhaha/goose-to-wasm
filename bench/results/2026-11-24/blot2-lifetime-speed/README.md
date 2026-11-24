# Blot2 class-keyed lifetime checker speedups (2026-11-24)

This batch climbs the self-hosted class-keyed lifetime checker bottleneck in `selfhost/checker_lifetimes.goose`, cutting default-2 GiB checking time by **3.59×** on frozen Blot2 `cb1e9e15` (`84.15 s → 23.42 s` paired on CPU 7; `-118 MiB` max RSS) and **2.70×** on frozen Blot2 `6ad5fbb` (`238.16 s → 88.28 s` solo), while also speeding up own-source `selfhost/main.goose` `--check` by **−8.3%** (`0.418 s → 0.383 s` on CPU 7) with byte-identical C and WebAssembly output and identical `forced0` soundness conformance.

## Pinned environment and inputs

- **Host:** `Linux cachyos-x8664 7.3.5-2-cachyos #1 SMP PREEMPT_DYNAMIC Fri, 20 Nov 2026 07:37:39 +0000 x86_64`
- **C compiler:** `clang version 23.1.5`
- **Repository base commit:** `ebe298d9c1bc09a3da9ff5a0c564875de26ab38c` (on top of Batch 3 `2f97b6daabcd47636f396fdbaf79dc5081984b59`)
- **Qualified Batch 4 compiler:**
  - Built by `scripts/qualify.py --output-dir build/qualify-blot2-speed --jobs 8`
  - Fixed-point C SHA-256 (`next_generation == third_generation`): `9914dd7c529d6400083d595c7650aed0a1e5b1f6f1127f55d65a9d7982be3378`
  - Executable SHA-256: `066cf2a01406ee978298953b653620b241c63c2cd6acb3dfe6a8e63f58159aaf`
- **Batch 3 baseline compiler (for alternating / paired comparison):**
  - `build/qualify-blot2-alts/bootstrap/bin/goose`, fixed-point C SHA-256 `f187e0eb…`, executable SHA-256 `6ba2365f79dbc79add229df99ea5f23a5c75b7ec56ed7d7cc73be8bb199c3572`
- **Plain upstream Goose reference check:** `build/native/goose` (`d5ae5bb`) on `selfhost/main.goose --stdlib stdlib`: **exit 0**
- **Threshold policy:** `LIFE_CONCRETE_FRAMES = 4096` kept unchanged; `native/runtime/*` untouched.
- **Frozen Blot2 snapshots (exported read-only from `../blot2` into `build/`, sibling untouched):**
  - `cb1e9e156d73c87c873f15888cd4fb6d2a399576` with Blot2's pinned stdlib (`build/blot-stdlib`)
  - `6ad5fbbd921d8c272667b5955085f479a99f5834` with repo `stdlib`

## What changed (`selfhost/checker_lifetimes.goose`)

Five profile-driven rounds of sound optimizations, all confined to `selfhost/checker_lifetimes.goose`:

1. **Round 1 — Hash buckets, `held_epoch` memoization, direct `l.scratch` transforms, shared `type_work`:**
   - Fixed `life_summary_bucket` to hash canonical `effect.places` (for `kind == 4`), `effect.value.type_id`, and `effect.field`, raised `life_summary_reserve` load factor to ≤ 0.5, and removed the dead `life_same_list` block in `life_effect_merge`.
   - Added `held_epoch` on `Lifetimes` and `epoch` on `LifeMapped`, caching all `life_map_set` and `life_typed_set` results before scanning `l.alts`; replaced heap-allocated `whole: i64[>..]` with fixed `i64[16]` stack storage and deduplicated `life_reached_places` in `life_replay`.
   - Added `LifeSet.slotread` caching (cleared in `life_reclaim_alts`), enabled `interior` caching with class frames, and routed 14 root-order-preserving transforms directly through `l.scratch` + `life_list_set(..., true)` without opening `LifeBuild`.
   - Added a `< 16`-element linear fast path in `LifeBuild` (deferring `l.build_slots` table allocation until promotion at `LIFE_BIG = 16`).
   - Replaced per-call local `work` grow arrays in `life_contains`, `life_holder_points`, and `life_refers` with a shared stack-disciplined `type_work: i32[>..]&` (eliminating per-call region prologues), fixed `life_pair_bucket` to a multiplicative hash at load ≤ 0.5, enlarged `l.refers`/`l.referable` to `65536`, and packed `life_alt_hash_step` / `life_assume_hash` into parallel multiply waves.
2. **Round 2 — Inline hash slots, `LifeCallSig` interning, and `life_replay` fast skips:**
   - Replaced parallel `list_slots`/`list_sets`/`list_keys` arrays with inline 16-byte `LifeListSlot { key: i64, set: i32, count: i32 }` (1 cache-line fetch instead of 4 per probe), shrank `LifeAtomSlot` to 16 bytes, and packed `LifeAssumeSlot { key: i64, at: i32, frame: i32 }`.
   - Added `LifeCallSig` interning (`call_sigs`/`call_sig_heads`/`call_sig_data`, cleared in `life_reclaim_alts`) keyed by `(target, island, map_sets/roots/types[0..base], active)` to share `map_memo` across identical repeated calls at `l.held_epoch == m.start_epoch`, skip unchanged `life_class_check` walks, and skip identical discovery `life_replay` calls within the same caller activation.
   - Added `life_replay` early skips before `life_map_set` (skip `kind == 3` when `omit_construct_reads || reading_place > 0`; skip pure-effect kinds `1, 2, 3, 8` in discovery when `l.island == 0 && life_nearest_recursive(l, l.frame) == 0`; skip `life_map_value` when store `places == 0` and on single-set effects).
   - Keyed discovery `life_leaf` and `life_offer_repeated` by `site = -2` for kinds `1, 2, 3, 8` when `l.class_frames > 0`, added single-element fast path in `life_live_contents`, and switched `life_shrink_places` to direct `l.scratch`.
3. **Round 3d — `LifeSet.flags` global-only short-circuit and SCC-safe discovery clean-frame skipping:**
   - Added `LifeSet.flags` bit 0 (`LIFE_SET_GLOBAL_ONLY = 1`, set in `life_insert` and `life_list_set`), short-circuiting **60.8%** (`48.7M / 80.2M`) of all `life_map_set` calls at entry before touching `map_memo` or `l.alts`.
   - Implemented Tarjan-SCC-safe discovery clean-frame skipping (`life_class_frame_is_clean` + `life_value_same`) for class-keyed islands in `life_class_eval` / `life_class_call`, tracking per-frame `recursive_call`, `stored_version`, `dep_change_stamp`, `dep_callees`/`dep_callee_stamps`, `dep_in_rec` (interior SCC nodes never skipped as direct entries), and exact global-live/ref equivalence across the discovery→validation reset (`life_cls_global_ok` via `global_refs_epoch` + `global_live_count` vs `settled_global_*`).
4. **Round 4b — Per-root global dependency tracking with zero-cost `LifeSet.flags` filtering:**
   - Replaced coarse `global_contents_epoch` with exact per-root `dep_roots` + `root_stamps` tracking across all 5 global-root `.contents` read sites (`life_note_places_read`, `life_overlay`, `life_gs_value`, `life_held_own`, `life_eval_name`), cutting discovery evaluations by **−26.3%** on `cb1e9e15` (`78,407 → 57,771`, saving `20,636` evals) and **−40.0%** on `6ad5fbb` (`221,955 → 133,254`, saving `88,701` discovery evals; `267,854 → 183,520` total, **−31.5%**).
   - Added `LIFE_SET_HAS_GLOBAL = 2` and `LIFE_SET_HAS_CLASS = 4` bits on `LifeSet.flags` (computed during existing root loads in `life_insert`/`life_list_set`) so `life_note_places_read` and `life_overlay` short-circuit in one branch, plus `dep_root_floor`-guarded consecutive stack dedup and in-place reuse of `dep_roots`/`dep_callees` storage.
5. **Round 5 — Cache-line struct packing, zero-copy `life_build_end`, and single-probe assumption lookup:**
   - Reordered `LifeAlt` (`32 B → 28 B` C struct), shrank `LifeAssume` (`56 B → 28 B`, −50%), packed `LifeMapped` to `16 B` (`24 B → 16 B`, exact quarter cache line with zero cache-line splits, `4.19 MB` total), and shrank `LifeJoin` to `12 B` (`24 B → 12 B`, −50%, caching all non-trivial joins in `life_join_slow` to avoid `life_list_set` DRAM misses).
   - Eliminated the `build_alts → scratch` double copy in `life_build_end` via direct `life_build_sort` / `life_build_list_set` with a 2-element inline sort fast path.
   - Combined `life_assumed` + `life_assume_open` into a single-probe `life_assume_probe` and halved `assume_slots` resize target (`4× → 2×`), added `LifeRoot.slotread_set` O(1) cache in `life_single`, and skipped `life_effect_merge`/`life_effect_indexed` probes when a frame has no recorded effects yet (`last < 0`).

## Round-by-round development progression (`build/dev2/bin/goose`, default 2 GiB)

| Stage | `cb1e9e15` wall / max RSS | `6ad5fbb` wall / max RSS | Speedup vs Batch 3 (`cb1e9e15` / `6ad5fbb`) |
|---|---:|---:|---:|
| Batch 3 baseline (`6ba2365f…`, dated) | `87.62 s` / `3.58 GiB` | `238.16 s` / `7.53 GiB` | `1.00×` / `1.00×` |
| Round 1 (hash, `held_epoch`, `scratch`, `type_work`) | `44.15 s` / `3.64 GiB` | `118.51 s` / `7.64 GiB` | `1.98×` / `2.01×` |
| Round 2 (inline slots, `LifeCallSig`, replay skips) | `40.27 s` / `3.81 GiB` | `105.92 s` / `7.94 GiB` | `2.18×` / `2.25×` |
| Round 3d (`GLOBAL_ONLY`, SCC-safe clean-frame skip) | `22.66 s` / `3.66 GiB` | `88.15 s` / `7.72 GiB` | `3.87×` / `2.70×` |
| Round 5 (`dev2`, load ~4.1, CPU `22.24 s` / `80.92 s`) | `22.95 s` / `3.47 GiB` | `83.02 s` / `7.89 GiB` | `3.82×` / `2.87×` |
| **Qualified Batch 4 (`066cf2a0…`, release)** | **`23.42 s` (CPU 7 paired) / `3.47 GiB`** | **`88.28 s` (CPU `84.56 s`) / `7.74 GiB`** | **`3.59×` (paired) / `2.70×`** |

Note: the host had moderate background load (`load average: 4.0–7.0`) during the Round 5 and final release measurements compared to the idle machine during Round 3d; on the paired same-load CPU-7 run below, Batch 4 beats Batch 3 `84.15 s → 23.42 s` (`3.59×` wall, `3.58×` CPU).

## Sampling profile and pass-trace evidence

`SIGPROF` sampling (`build/prof-perf/sampler.so`, `-O2 -g -fno-omit-frame-pointer`) confirmed the post-optimization profile is flat with no remaining dominant algorithmic hotspot:

- **`6ad5fbb` (118,643 symbolized samples, Round 3d):** `life_list_set` `12.5%`, `life_effect` `9.6%`, `life_build_*` `~15%`, `life_map_set` `4.4%`, `life_contains` `4.4%`, `life_assume_slot` `4.1%`, `life_replay` `3.4%`, `life_join_slow` `3.0%`, `life_body` `2.7%`, `life_reclaim_alts` `1.5%`. The #1 inlined leaf was `g_store_nn_35` (`LifeAlt` copying, `10.1%`), directly motivating Round 5's `LifeAlt` shrink and zero-copy `life_build_end`.
- **`cb1e9e15` (35,761 symbolized samples, Round 4b):** `life_list_set` `10.5%`, `life_effect` `9.5%`, `life_map_set` `7.6%`, `life_assume_slot` `4.6%`, `life_replay` `4.0%`, `life_join_slow` `3.7%`, `life_leaf` `3.6%`, `life_contains` `3.5%`, with the top hot lines being L3/DRAM misses on hash-table probes (`summary_heads`, `list_slots`, `assume_slots`, `map_memo`, `joins`, `atom_slots`), directly motivating Round 5's compact struct layouts and single-probe lookups.
- **Per-pass evaluation counts (`cb1e9e15` and `6ad5fbb`):**
  - `cb1e9e15` Round 3d → Round 4b: discovery evals `78,407 → 57,771` (`-26.3%`; Pass 3 `19,076 → 6,633`, Pass 4 `12,410 → 4,223`, Pass 3 wall `-23%`, Pass 4 wall `-19%`, Validation wall `-17%`).
  - `6ad5fbb` Round 3d → Round 4b: discovery evals `221,955 → 133,254` (`-40.0%`; Pass 3 `45,843 → 15,943`, Pass 4 `45,729 → 7,279`, Pass 5 `24,461 → 4,832`), total evals `267,854 → 183,520` (`-31.5%`).

## Rejected experiments (preserved)

1. **Disabling `l.leaves` stamping when `l.class_frames > 0` (Round 3a):**
   - *Hypothesis:* `life_offer_repeated` already handles intra-activation dedup in O(1), so skipping `life_leaf` stamping in class mode would save `~1.21M` `LifeLeaf` allocations (`~100 MB`) and `~4.6%` CPU.
   - *Measured outcome:* `cb1e9e15` dropped to `36.70 s`, but **`6ad5fbb` regressed `105.92 s → 161.02 s` (+55.1 s)**.
   - *Diagnosis:* `life_offer_repeated` disables inside recursive functions (`life_nearest_recursive(l, l.frame) > 0`), whereas `life_leaf` still deduplicates non-recursive leaves inside recursive callers such as `checkExpr`/`checkStmt`. Reverted (kept `site = -2` normalization in discovery).
2. **Memoizing `dep_clean_pass`/`dep_dirty_pass` with per-revision `cls_dirty_epoch` instead of `l.pass` (Round 3a/3b):**
   - *Hypothesis:* Using a fine-grained dirty epoch would allow re-checking cleanliness within the same pass after unrelated revisions.
   - *Measured outcome:* **`6ad5fbb` regressed `105.92 s → 166.24 s` (+60.3 s)** and max RSS rose `7.94 → 8.29 GiB`.
   - *Diagnosis:* `cls_dirty_epoch` incremented `100,000+` times per pass, defeating BFS memoization and causing `O(N^2)` transitive call-graph traversals on every `life_class_call`. Replaced with per-`l.pass` memoization (matching concrete `life_frame_is_clean`) and direct invalidation on `life_class_check`/change.
3. **Unfiltered per-root `dep_roots` scanning in `life_note_places_read` without `LifeSet.flags` / floor-dedup / in-place reuse (Round 4a):**
   - *Measured outcome:* `cb1e9e15` regressed `22.66 s → 23.74 s` and `6ad5fbb` regressed `88.15 s → 92.06 s` (`+210 MiB` RSS, `7.72 → 7.93 GiB`).
   - *Diagnosis:* Scanning `l.alts` + `l.roots` on every `life_contents_plain` call in class mode and appending duplicate `dep_roots` on every re-evaluation outweighed the skipped passes. Fixed in Round 4b with `LIFE_SET_HAS_GLOBAL` / `LIFE_SET_HAS_CLASS` bits, `dep_root_floor` consecutive dedup, and in-place `dep_roots`/`dep_callees` reuse.

## Qualification results

`build/qualify-blot2-speed/summary.json` (total `311.3 s`, **all stages exit 0**):

| Stage | Exit | Time | Summary |
|---|---:|---:|---|
| Plain upstream check (`build/native/goose`) | 0 | — | Own compiler source checks cleanly |
| `bootstrap` (`--verify`) | 0 | 144.7 s | Fixed point `9914dd7c…`, executable `066cf2a0…` |
| `conformance` (`-O0`, `-O2`, gcc) | 0 | 104.4 s | `10,697/10,801` (104 recorded gaps, 0 unexpected) |
| `native-checks` (`native/tests/check.py`) | 0 | 12.1 s | `54 steps ok` |
| `conformance-memory64` | 0 | 166.5 s | `4,771/4,779` (8 recorded gaps, 0 unexpected) |
| `unit-tests` (19 modules) | 0 | 56.7 s | All passed |

## Forced-class (`LIFE_CONCRETE_FRAMES = 0`) conformance audit

Measured on a separate scratch source copy (`build/forced0-b4/`, `tests/conformance.py --frontend-only --jobs 8`) against the Batch 1 `forced0` baseline (`build/conformance-forced0-exp-ae/report.json`):

| Build | Total failing rows (10,801) | New failures vs Batch 1 | Fixed vs Batch 1 | Upstream sentinel errors | `selfhost/main.goose` check |
|---|---:|---:|---:|---:|:---:|
| Batch 1 (`exp-ae`, `forced0`) | 126 (`78` known gaps + `48` forced0-only) | — | — | 13/13 rejected | exit 0 |
| Batch 3 (`forced0-b3`) | 126 (`78` known gaps + `48` forced0-only) | 0 | 0 | 13/13 rejected | exit 0 |
| **Batch 4 (`forced0-b4`)** | **126** (`78` known gaps + `48` forced0-only) | **0** | 0 | **13/13 rejected** | **exit 0** |

## Final pinned release compiler measurements

### Own-source alternating 5-round comparison (CPU 7, `selfhost/main.goose --stdlib stdlib`)

| Workload | Batch 3 (`6ba2365f…`) wall / CPU | Batch 4 (`066cf2a0…`) wall / CPU | Delta (wall / CPU) | Output |
|---|---:|---:|---:|---|
| `--check` | `0.418 s` / `0.398 s` | **`0.383 s` / `0.375 s`** | **−8.3% / −5.8%** | — |
| `--target c -O2` | `0.719 s` / `0.695 s` | **`0.712 s` / `0.688 s`** | **−1.0% / −1.0%** | `21,910,353 B` (`cf1aeaf07ad3…`, byte-identical) |
| `--target wasm-direct -O2` | `0.550 s` / `0.534 s` | **`0.528 s` / `0.512 s`** | **−4.0% / −4.1%** | `4,046,815 B` (`33bbe0fa9caa…`, byte-identical) |

Raw 5-round CPU-7 wall timings:
- `--check`: Batch 3 `[0.418, 0.390, 0.404, 0.428, 0.450]`, Batch 4 `[0.414, 0.377, 0.375, 0.393, 0.383]`
- `--target c -O2`: Batch 3 `[0.737, 0.719, 0.719, 0.717, 0.832]`, Batch 4 `[0.706, 0.711, 0.712, 0.759, 0.719]`
- `--target wasm-direct -O2`: Batch 3 `[0.536, 0.550, 0.538, 0.554, 0.595]`, Batch 4 `[0.528, 0.521, 0.528, 0.530, 0.529]`

### Frozen Blot2 checks under default 2 GiB `--stack-reserve`

| Snapshot | Run type | Compiler | Wall | CPU (`u+s`) | Max RSS | Speedup | Diagnostics |
|---|---|---|---:|---:|---:|---:|---|
| `cb1e9e15` | Paired CPU 7 (same load) | Batch 3 (`6ba2365f…`) | `84.15 s` | `83.06 s` | `3.583 GiB` | — | 1 (`check/check.goose:3422:86`) |
| `cb1e9e15` | Paired CPU 7 (same load) | **Batch 4 (`066cf2a0…`)** | **`23.42 s`** | **`23.18 s`** | **`3.468 GiB`** | **3.59× (−72.2%)** | 1 (`check/check.goose:3422:86`) |
| `cb1e9e15` | Solo (unpinned) | **Batch 4 (`066cf2a0…`)** | **`24.35 s`** | **`23.35 s`** | **`3.468 GiB`** | **3.60× vs dated `87.62 s`** | 1 (`check/check.goose:3422:86`) |
| `6ad5fbb` | Dated reference run | Batch 3 (`6ba2365f…`) | `238.16 s` | — | `7.53 GiB` | — | 1 (`check/check.goose:3179:86`) |
| `6ad5fbb` | Solo (unpinned) | **Batch 4 (`066cf2a0…`)** | **`88.28 s`** | **`84.56 s`** | `7.741 GiB` | **2.70× (−62.9%)** | 1 (`check/check.goose:3179:86`) |
