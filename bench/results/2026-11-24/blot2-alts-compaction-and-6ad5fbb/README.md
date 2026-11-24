# Blot2 `l.alts` memory compaction and end-to-end native `6ad5fbb` build (2026-11-24)

This batch reduces peak `l.alts` memory usage during class-keyed lifetime checking so archived Blot2 `6ad5fbb` (the full pre-cut scoped compiler) checks and compiles natively inside the **default 2 GiB `--stack-reserve`**, fixes an optimizer exit-retargeting bug surfaced by `6ad5fbb`'s `-O2` C build, and qualifies an end-to-end native release build and WebAssembly benchmark run of `6ad5fbb`.

## Pinned environment and inputs

- **Repository base commit:** `29b30c26181a9642d38aa83adf2e311542365e2c` (Batch 2: C-host build interface & native `cb1e9e15` build)
- **Qualified Batch 3 compiler:**
  - Built by `scripts/qualify.py --output-dir build/qualify-blot2-alts --jobs 8`
  - Fixed-point C SHA-256 (`next_generation == third_generation`): `f187e0ebcddefdceea828b9345275947f81610589b9384a61180cd787b7429b4`
  - Executable SHA-256: `6ba2365f79dbc79add229df99ea5f23a5c75b7ec56ed7d7cc73be8bb199c3572`
- **Batch 2 baseline compiler (for alternating comparison):**
  - `build/qualify-blot2-chost-v2/bootstrap/bin/goose`, executable SHA-256: `51fbbebd08266da3fa52862be7629c4f925fcd9f80573746786d00a203cfb6a6`
- **Plain upstream Goose reference check:** `build/native/goose` (`d5ae5bb`) on `selfhost/main.goose --stdlib stdlib`: **exit 0**
- **Host tool versions:** `clang 23.1.5`, `node v26.5.0`, `rustc 1.96.0-nightly (3645249d7 2026-03-16)`
- **Threshold policy:** `LIFE_CONCRETE_FRAMES = 4096` kept unchanged.
- **Frozen Blot2 snapshots (exported read-only from `../blot2` into `build/`, sibling untouched):**
  - `cb1e9e156d73c87c873f15888cd4fb6d2a399576` with Blot2's pinned stdlib (`build/blot-stdlib`)
  - `6ad5fbbd921d8c272667b5955085f479a99f5834` with repo `stdlib`
  - For the end-to-end `6ad5fbb` native build (`build/blot2-e2e-6ad5fbb/`), the scratch archive copy applies the same 1-line sound §5.2 `finishReflection` grow-only sort-buffer workaround on `compiler-goose/src/check/check.goose:1964` (patched `check.goose` SHA-256: `5c1be90ed02fd642…`).

## What changed

### 1. Canonical `root`-sorted `LifeSet` representation and removal of `l.set_index` (`selfhost/checker_lifetimes.goose`)

Pre-change profiling on `6ad5fbb` (`--stack-reserve 8G`) showed `l.alts` peaking at **128.82M** alternatives (`3.48 GB`, exceeding the `79.5M` 2 GiB cap during Pass 2 at `85.45M`) plus **155.11M** entries in `l.set_index` (`620 MB`), with **31.3%** (`40.36M`) order-only duplicate alternatives, **1.41M** duplicate singletons in `l.list_sets`, and only **22.2%** (`28.62M` alts) live at validation end.

- Removed `LifeSet.index`, `LifeSet.index_mask`, `l.set_index`, and `life_index_build` (`-620 MB` on `6ad5fbb`).
- Stored every `LifeSet` as a canonical `root`-ascending contiguous span `l.alts[first .. first + count]` (with forward `next` links preserved for all existing traversal loops), sorted via `life_scratch_sort` (already-sorted-prefix linear fast path, insertion sort for small/near-sorted tails, iterative median-of-3 quicksort with zero allocations).
- Unified `life_alt_set` and `count == 1` in `life_list_set` through `life_single`, eliminating duplicate singletons.
- Replaced `life_find` with contiguous linear (`< 8`) / binary search (`>= 8`), simplified `life_equal` / `life_same_list` to `O(1)` (`a == b`), updated `life_subset` to sorted advancing-`lo` binary search (`cb * 4 < ca`) / two-pointer scan, and updated `life_join_slow` to commutative `l.joins` lookup + fast `life_subset` early-out + single-pass sorted two-pointer merge (`already_sorted = true`).

### 2. Memo-preserving inter-pass `l.alts` mark-and-compact GC (`selfhost/checker_lifetimes.goose`)

- Added `life_reclaim_alts(l, standalone)` to mark all live `LifeSet` IDs reachable from `standalone`, `roots`, `cells`, `frames`, `exits`, `effects`, `leaves`, `holds`, live `items`, and `atoms`.
- Compacts `l.alts` in place while keeping live `LifeSet` IDs unchanged (preserving strictly increasing `first` order), updates `l.atom_slots[i].alt`, and rebuilds `l.list_sets` / `l.list_keys` / `l.list_slots` for live `count >= 2` sets.
- Evicts only entries referencing reclaimed set IDs from `l.summaries`, `l.roots[i].stores`, `l.sets[s].{bound_*,plain,folded,lasting,interior}`, `l.joins`, `l.contents_memo`, `l.loaded`, `l.referable`, `l.local_reads`, `l.readbacks`, `l.inexact_reads`, `l.far_cache`, and `l.offers`, preserving live memoized results across compaction.
- Adaptive trigger in `life_check_attempt`: starts at `28M` alts, advances to `clamp(live + 20M, 28M, 44M)` after each discovery reclaim, and runs before validation only if `l.alts.len > 36M`.

### 3. Optimizer `opt_replace` exit-retargeting fix (`selfhost/optimizer.goose`, `tests/test_cli_outputs.py`)

- Building `6ad5fbb` at `-O2` surfaced `reuse/restart_cache.goose:79: error: c: jump has no enclosing loop or early block` on `if detached_writes && self_.startDetached(...)` (`let detached_writes = true`): `self_.startDetached(...)` inlined into an `F_EARLY` `N_BLOCK` whose `return`s became `N_BREAK` targeting the right operand, and constant-folding `true && right` via `opt_replace(p, o, node, right)` moved the `F_EARLY` block to node ID `node` without retargeting its `N_BREAK`s.
- Fixed `opt_replace` to call `check_retarget_exits(p, destination, source, destination)` and transfer `OPT_HAS_BREAK` whenever moving an `F_EARLY` `N_BLOCK` or loop (`N_LOOP` / `N_FOR` / `N_WHILE`) to a new node ID, covering all constant-folding (`if`, `&&`, `||`) and inlining sites uniformly.
- Added the `folded_inline_exits` regression (`always_true && early_check(n)`, `always_false || early_check(...)`, `if always_true { ... }`) to `CHostLibraryBuild.test_native_codegen_regressions` in `tests/test_cli_outputs.py`.

## Qualification results

`build/qualify-blot2-alts/summary.json` (total `298.1 s`, **all stages exit 0**):

| Stage | Exit | Time | Summary |
|---|---:|---:|---|
| Plain upstream check (`build/native/goose`) | 0 | — | Own compiler source checks cleanly |
| `bootstrap` (`--verify`) | 0 | 131.7 s | Fixed point `f187e0eb…`, executable `6ba2365f…` |
| `conformance` (`-O0`, `-O2`, gcc) | 0 | 103.2 s | `10,697/10,801` (104 recorded gaps, 0 unexpected) |
| `native-checks` (`native/tests/check.py`) | 0 | 12.3 s | `54 steps ok` |
| `conformance-memory64` | 0 | 166.3 s | `4,771/4,779` (8 recorded gaps, 0 unexpected) |
| `unit-tests` (19 modules) | 0 | 57.6 s | All passed, including `folded_inline_exits` regression |

## Forced-class (`LIFE_CONCRETE_FRAMES = 0`) conformance audit

Measured on a separate scratch source copy (`build/forced0-b3/`, `tests/conformance.py --frontend-only --jobs 8`) against the Batch 1 `forced0` baseline (`build/conformance-forced0-exp-ae/report.json`):

| Build | Total failing rows (10,801) | New failures vs Batch 1 | Fixed vs Batch 1 | Upstream sentinel errors | `selfhost/main.goose` check |
|---|---:|---:|---:|---:|:---:|
| Batch 1 (`exp-ae`, `forced0`) | 126 (`78` known gaps + `48` forced0-only) | — | — | 13/13 rejected | exit 0 |
| Batch 3 (`forced0-b3`) | **126** (`78` known gaps + `48` forced0-only) | **0** | 0 | **13/13 rejected** | **exit 0** |

## `l.alts` memory profile (before vs after Batch 3)

Measured via scratch instrumentation (`build/prof-alts/` before vs `build/prof-alts-b3/` after):

| Metric | `cb1e9e15` (after) | `6ad5fbb` (before, `--stack-reserve 8G`) | `6ad5fbb` (after, **default 2 GiB**) | Change on `6ad5fbb` |
|---|---:|---:|---:|---:|
| Discovery compactions | `0` | `0` | `8` (Pass 1–8) | — |
| Peak `l.alts` count | `29,416,802` (`794 MB`, 37.0% of 2 GiB) | `128,820,326` (`3.48 GB`) | **`46,418,106`** (`1.25 GB`, 58.4% of 2 GiB) | **−64.0%** |
| Peak `l.set_index` count | `0` | `155,114,048` (`620 MB`) | **`0`** | **−100% (−620 MB)** |
| Combined `l.alts + l.set_index` peak | `794 MB` | `4.10 GB` | **`1.25 GB`** | **−69.5%** |
| Validation-end `l.alts` | `29,416,802` | `128,820,326` | `38,277,034` | −70.3% |
| Fits in default 2 GiB `--stack-reserve` | yes | no (overflowed Pass 2 at `85.45M`) | **yes** (> 890 MB headroom) | — |

Per-pass compaction trace on `6ad5fbb` (`build/prof-alts-b3`):
- Pass 1: `31.19M → 6.80M` (`-78.2%`)
- Pass 2 (peak): `46.42M → 11.25M` (`-75.8%`)
- Pass 3: `41.16M → 12.95M`; Pass 4: `36.97M → 13.64M`; Passes 5–8: `~36.4M → ~13.99M`
- Validation end: `38.28M` (`14.42M` sets, `2.78M` live lists, `2.14M` atoms)

## Rejected / superseded intermediate tuning (preserved)

The first Lever 1+2 draft used a fixed `16M` compaction threshold, wiped all memo tables (`joins`, `contents_memo`, `loaded`, `referable`, `local_reads`, `readbacks`, `inexact_reads`, `far_cache`, `offers`, `sets[s].*`, `roots[i].stores`) on every reclaim, used heapsort in `life_scratch_sort`, and omitted the `life_subset` early-out in `life_join_slow`:

| Variant (`build/dev2/bin/goose`, default 2 GiB) | `cb1e9e15` time / max RSS | `6ad5fbb` time / max RSS | Diagnosis |
|---|---:|---:|---|
| Draft 1 (`16M` threshold, full cache wipe, heapsort, no `life_subset` fast path) | `97.12 s` / `3.44 GiB` | `236.51 s` / `7.48 GiB` | Compaction thrashed every pass on `cb1e9e15` and twice on settle, discarding memoized joins/readbacks; `life_join_slow` copied entire large sets into `l.scratch` on no-op joins |
| **Final (`28M` adaptive threshold, live-entry memo filtering, quicksort, `life_subset` fast path)** | **`77.01 s`** (`-20.7%`) / `3.58 GiB` | **`223.52 s`** (`-5.5%`) / `7.60 GiB` | 0 compactions on `cb1e9e15`; preserves live memo entries across `6ad5fbb` compactions |

## Solo Blot2 and alternating own-source measurements (qualified release compilers)

### Own-source alternating 5-round comparison (`selfhost/main.goose --stdlib stdlib`)

| Workload | Batch 2 (`51fbbebd…`) | Batch 3 (`6ba2365f…`) | Delta | Output |
|---|---:|---:|---:|---|
| `--check` | `0.481 s` | **`0.458 s`** | **−4.6%** | — |
| `--target c -O2` | `0.798 s` | **`0.785 s`** | **−1.6%** | `23,251,828 B` (byte-identical) |
| `--target wasm-direct -O2` | `0.590 s` | **`0.571 s`** | **−3.2%** | `3,998,365 B` (byte-identical) |

### Frozen Blot2 solo checks under default 2 GiB `--stack-reserve`

| Snapshot | Compiler | Stack reserve | Elapsed | Max RSS | RSS delta vs prior | Diagnostics |
|---|---|---:|---:|---:|---:|---|
| `cb1e9e15` | Batch 1 (`7a08e2ee…`) | 2 GiB | `73.50 s` | `5.21 GiB` | — | 1 (`check.goose:3422:86`) |
| `cb1e9e15` | **Batch 3 (`6ba2365f…`)** | **2 GiB** | `87.62 s` | **`3.58 GiB`** | **−31.3%** | 1 (`check.goose:3422:86`) |
| `6ad5fbb` | Batch 1 (`exp-ae-8g`) | **8 GiB** (2 GiB crashed) | `215.51 s` | `10.40 GiB` | — | 1 (`check.goose:3179:86`) |
| `6ad5fbb` | **Batch 3 (`6ba2365f…`)** | **2 GiB (default)** | `238.16 s` | **`7.53 GiB`** | **−27.6%** | 1 (`check.goose:3179:86`) |

## End-to-end native Blot2 `6ad5fbb` build and `.blot` execution

Built archived `6ad5fbb` (scratch copy with 1-line §5.2 `finishReflection` sort-buffer patch) using Blot2's exact C-host flags (`-std=gnu11 -D_GNU_SOURCE -O2 -pthread`, linking `blot_goose.c`, 6 `native/*.o`, `goose_runtime.o`, `-lm`, with **no `-rdynamic`** and **no `-ldl`**) under the **default 2 GiB `--stack-reserve`** (`build/dev2/bin/goose`, identical Batch 3 source):

| Stage | Time | Max RSS | Output | Size / SHA-256 |
|---|---:|---:|---|---|
| `--emit-runtime goose_runtime.c` | `0.02 s` | `12.1 MiB` | `goose_runtime.c` | `142,148 B` |
| Compile `goose_runtime.c` + 6 `native/*.c` (`-O2`) | `0.63 s` | `111.9 MiB` | `goose_runtime.o` + 6 `*.o` | — |
| Emit program (`-O2 --header --expansion-node-limit 1000000`) | `295.51 s` | `8.28 GiB` | `blot_goose.c`, `blot_goose.h` | `381,933,974 B` (`38368a15…`), `194 B` (`d0fce2e5…`) |
| Clang compile & link release (`-O2`) | `319.05 s` | `9.57 GiB` | `blotc-goose` | `22,079,320 B` (`b4de1363…`) |

Dynamic dependencies (`ldd blotc-goose`): only `libm.so.6` and `libc.so.6` (plus `linux-vdso.so.1` and loader).

### WebAssembly execution verification (`9/9` grammar-compatible idiomatic benchmarks bit-exact vs Rust)

Archived `6ad5fbb` predates Blot2 commit `de15d314` ("Goose port: the store statement in the parser, checker and Core lowering"), so `a[i] = v` store statements (used in `std/prelude.blot:324-328`, `std/array.blot:29`, `histogram.blot`, `matrix_multiply.blot`, and `prime_sieve.blot`) are not yet parsed by `6ad5fbb`'s own parser. Using a scratch copy of `std/prelude.blot` omitting those three `*.write` store-statement helpers (and scaling `csv_numbers`/`decimal_format` identically to `0..16` for pre-`f730b31e` `std/text.blot`), all **9/9** grammar-compatible `benchmarks/idiomatic/*.blot` programs compile to valid WebAssembly with `6ad5fbb`'s `blotc-goose` and match `rustc -O` bit-for-bit in Node `v26.5.0`:

| Benchmark | `.wasm` bytes | `blotc-goose` wall (µs) | Rust `run(1)` | `blotc-goose` `run(1)` | Match |
|---|---:|---:|---:|---:|:---:|
| `csv_numbers_16` | 12,956 | 56,256 | `491544` | `491544` | yes |
| `decimal_format_16` | 12,830 | 54,971 | `2062386165` | `2062386165` | yes |
| `expression_eval` | 8,108 | 63,047 | `0` | `0` | yes |
| `fibonacci` | 1,349 | 61,852 | `4004785664` | `4004785664` | yes |
| `gcd` | 8,093 | 55,384 | `59564` | `59564` | yes |
| `integer_recurrence` | 1,292 | 55,453 | `2144605973` | `2144605973` | yes |
| `list_pipeline` | 14,243 | 64,288 | `3139584` | `3139584` | yes |
| `option_pipeline` | 6,784 | 58,087 | `322174978` | `322174978` | yes |
| `tree_reduce` | 7,853 | 59,184 | `2505396224` | `2505396224` | yes |
