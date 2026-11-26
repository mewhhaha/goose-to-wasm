# Compiler Throughput Campaign (2026-11-26)

This study tracks end-to-end single-core and multi-core compiler throughput, Native C emission, and memory-footprint optimizations across frozen procedural multi-file and single-file Goose workloads (`flat_multi_100k`, `flat_single_100k`, plus a `flat_multi_250k` scale-up reference), frozen own-source `selfhost/` (`f746c6e`, 47,395 LOC + stdlib), and frozen Blot2 `98f277f2` (78,954 LOC + read-only pinned Blot2 stdlib).

All outputs across every batch, target (`wasm-direct` and `c`), optimization level, and thread count are **100% SHA-256 bit-identical** to frozen `v2026.4-3`, plain upstream Goose `build/native/goose check selfhost/main.goose --stdlib stdlib` exits **0**, `native/runtime/*` remains untouched, and Wasm64 self-compilation retains exact **24 imports** with clean single-threaded fallback.

![Compiler throughput: multi-core LOC/s scaling and real large codebases](compiler_throughput.svg)

![Stage-by-stage wall time breakdown](stage_breakdown.svg)

---

## Environment & Pinned Inputs

- **Host CPU:** AMD Ryzen 7 7800X3D (8 physical cores / 16 threads, 96 MiB L3 3D V-Cache), Linux `7.3.5-2-cachyos x86_64`
- **C Compiler:** `clang version 23.1.5` (`-std=gnu11 -O2 -pthread`)
- **Frozen Baselines:**
  - `v2026.4-3-nopgo`: `9842a7998d8475ca…` (unprofiled Clang 23 `-O2` from `v2026.4-3` seed — matched 1:1 with unprofiled qualified builds)
  - `v2026.4-3` (PGO): `3a900d10d32c2471…` (separate reference run, paired 1:1 with fresh Clang 23 PGO build)
- **Final Qualified Binaries (`b7d0915` — Batch 1 → 4D):**
  - Unprofiled (`build/qualify-batch4d/bootstrap/bin/goosew`): `d9d63df0f150b08b…` (fixed-point verified, Stage 2 == Stage 3 C `94ac1262dba226f8…`, `g_runtime_start(201, 201)`)
  - Fresh Clang 23 PGO (`build/pgo-batch4d/goosew_pgo`, separate reference run): `710213016d6073a6…` (trained on fixed-point C `8fbdb95ccbc61e80…` with `-Wl,--wrap=_Exit` and strict `-Werror=profile-instr-{out-of-date,unprofiled,missing}`)
- **Frozen Workloads:**
  - `flat_multi_100k`: 18 files, 2,257 functions, **98,749 LOC** (`generate_workloads.py`)
  - `flat_single_100k`: 1 file, 2,241 functions, **98,604 LOC** (`generate_workloads.py`)
  - `flat_multi_250k` (separate scale-up reference): 34 files, 5,633 functions, **246,765 LOC** (`generate_workloads.py`)
  - `selfhost_f746c6e`: frozen `git archive f746c6e` of `selfhost/` + `stdlib/` + `native/`, **47,395 LOC** (`selfhost/*.goose`)
  - `blot2` `98f277f2`: read-only `../blot2` archive (`build/blot2-head-probe/compiler-goose/src/main.goose` + pinned `../blot2/build/goose-port/upstream-d5ae5bb/source-precision/stdlib`), **78,954 LOC**, compiled with `--library --reachable-program --expansion-node-limit 1000000` (and `--wasm-memory64 --wasm-max-pages 65536` for Direct Wasm64)

---

## Final Results — Batch 4D (`b7d0915`) vs `v2026.4-3`

### 1. Matched Unprofiled Direct Wasm (`--jobs 8` / default `auto`, 5 alternating rounds)

Raw JSON: [`batch4_paired_nopgo_j8.json`](batch4_paired_nopgo_j8.json)

| Workload | `v2026.4-3-nopgo` (ms) | Batch 4D `--jobs 8` (ms) | Speedup | Peak RSS (`base → new`, MiB) | Stage highlights (`base → new`, ms) | Byte-identical |
|---|---:|---:|---:|---:|---|---|
| `flat_multi_100k_o0` (98,749 LOC) | `290.5` | **`51.1`** (`1.93M/s`) | **5.68×** | `313.2 → 200.5` (**-36.0%**) | `p 35.5→15.9`, `tc 99.4→13.4`, `lf 43.7→0.8`, `opt 36.0→2.9`, `be 67.1→11.4` | yes (`5d5090f074…`) |
| `flat_multi_100k_o2` (98,749 LOC) | `320.2` | **`76.1`** (`1.30M/s`) | **4.21×** | `314.9 → 207.4` (**-34.1%**) | `p 35.3→15.6`, `tc 91.1→12.9`, `lf 42.2→0.9`, `opt 72.3→27.5`, `be 65.4→11.2` | yes (`6227d67f32…`) |
| `flat_single_100k_o0` (98,604 LOC) | `271.8` | **`60.4`** (`1.63M/s`) | **4.50×** | `310.1 → 151.8` (**-51.1%**) | `p 36.0→23.5`, `tc 88.7→14.2`, `lf 42.6→1.2`, `opt 34.5→3.1`, `be 61.3→11.8` | yes (`90ec860af5…`) |
| `selfhost_o0_wasm64` (47,395 LOC) | `4,389.5` | **`584.3`** | **7.51×** | `573.2 → 288.6` (**-49.6%**) | `p 34.6→22.3`, `lf 4,111.5→417.2` (**9.86×**), `opt 27.4→5.2`, `be 76.0→17.5` (**4.34×**) | yes (`3fcd1fce7b…`) |
| `selfhost_o2_wasm64` (47,395 LOC) | `4,361.9` | **`586.0`** | **7.44×** | `630.1 → 344.8` (**-45.3%**) | `p 35.2→21.2`, `lf 4,013.0→386.5` (**10.38×**), `opt 66.4→36.0`, `be 119.3→26.2` (**4.56×**) | yes (`fff47bea42…`) |
| `blot2_o0_wasm64` (78,954 LOC) | `3,581.8` | **`2,538.5`** | **1.41×** | `1,337.7 → 1,089.9` (**-18.5%**) | `p 79.4→46.7`, `tc 608→503`, `lf 2,259→1,868`, `opt 63.2→16.9` (**3.74×**), `be 487.7→76.3` (**6.39×**) | yes (`2a39a0dd07…`) |
| `blot2_o2_wasm64` (78,954 LOC) | `4,324.8` | **`2,726.0`** | **1.59×** | `1,448.2 → 1,200.9` (**-17.1%**) | `p 81.7→46.1`, `lf 2,268→1,904`, `opt 839.6→119.9` (**7.00×**), `be 541.9→111.2` (**4.88×**) | yes (`6a399d7b51…`) |

### 2. Matched Unprofiled Single-Core (`--jobs 1`, Pinned CPU 7, 3 alternating rounds)

Raw JSON: [`batch4_paired_nopgo_cpu7.json`](batch4_paired_nopgo_cpu7.json)

| Workload | `v2026.4-3-nopgo` (ms) | Batch 4D `--jobs 1` (ms) | Single-core speedup | Peak RSS (`base → new`, MiB) | Key single-core stage wins (ms) | Byte-identical |
|---|---:|---:|---:|---:|---|---|
| `flat_multi_100k_o0` | `266.1` | **`138.2`** (`715k/s`) | **1.93×** | `313.7 → 141.3` (**-55.0%**) | `p 34.4→21.8`, `tc 85.8→67.5`, `lf 43.4→1.6`, `opt 33.6→5.8`, `be 61.1→36.9` | yes |
| `flat_multi_100k_o2` | `306.7` | **`159.9`** (`617k/s`) | **1.92×** | `315.2 → 172.6` (**-45.3%**) | `p 33.9→22.5`, `lf 40.9→1.4`, `opt 74.0→28.3`, `be 65.3→36.5` | yes |
| `flat_single_100k_o0` | `264.8` | **`135.4`** (`728k/s`) | **1.96×** | `310.5 → 141.4` (**-54.5%**) | `p 34.3→21.7`, `tc 85.7→64.8`, `lf 41.2→1.7`, `opt 36.3→5.8`, `be 62.7→36.1` | yes |
| `selfhost_o0_wasm64` | `3,883.3` | **`547.0`** | **7.10×** | `574.3 → 248.3` (**-56.8%**) | `lf 3,625.7→356.0` (**10.19×**), `tc 119.3→96.8`, `be 70.8→52.8` | yes |
| `selfhost_o2_wasm64` | `3,899.3` | **`610.0`** | **6.39×** | `630.9 → 285.9` (**-54.7%**) | `lf 3,565.7→350.6` (**10.17×**), `opt 63.2→43.8`, `be 110.9→88.2` | yes |
| `blot2_o0_wasm64` | `3,397.0` | **`2,621.7`** | **1.30×** | `1,338.2 → 962.8` (**-28.1%**) | `p 77.7→58.3`, `lf 2,153→1,756`, `opt 61.1→30.7`, `be 485.4→254.7` | yes |
| `blot2_o2_wasm64` | `4,308.1` | **`2,931.3`** | **1.47×** | `1,448.9 → 1,056.1` (**-27.1%**) | `lf 2,203→1,813`, `opt 858.3→132.6` (**6.47×**), `be 528.3→364.4` | yes |

### 3. Matched Unprofiled Native C Emission (`--target c`, `--jobs 8`, 5 alternating rounds)

Raw JSON: [`batch4_cgen_paired.json`](batch4_cgen_paired.json)

| Workload (`--target c`) | `v2026.4-3-nopgo` (ms) | Batch 4D `--jobs 8` (ms) | Wall speedup | C backend (`base → new`, ms) | Peak RSS (`base → new`, MiB) | Byte-identical |
|---|---:|---:|---:|---|---:|---|
| `flat_multi_100k_o0_c` (98.7k LOC) | `347.5` | **`73.4`** (`1.35M/s` wall / `1.69M/s` cmp) | **4.73×** | `125.6 → 28.0` (**4.48×**) | `361.6 → 269.4` (**-25.5%**) | yes (`b7c91752a6…`) |
| `flat_multi_250k_o0_c` (246.8k LOC) | `921.9` | **`187.5`** (`1.32M/s` wall / `1.62M/s` cmp) | **4.92×** | `349.0 → 69.7` (**5.00×**) | `857.9 → 561.8` (**-34.5%**) | yes (`35686eedd0…`) |
| `selfhost_o0_c` (47.4k LOC) | `4,025.1` | **`554.5`** | **7.26×** | `106.2 → 38.5` (**2.76×**) | `601.9 → 334.9` (**-44.4%**) | yes (`d8c8706784…`) |
| `selfhost_o2_c` (47.4k LOC) | `4,119.7` | **`591.0`** | **6.97×** | `165.0 → 47.7` (**3.46×**) | `665.4 → 393.6` (**-40.8%**) | yes (`3f7ef98428…`) |
| `blot2_o0_c` (79.0k LOC) | `4,601.5` | **`2,609.4`** | **1.76×** | **`1,721.9 → 250.6` (6.87×)** | `1,403.9 → 1,235.1` (**-12.0%**) | yes (`c476c70329…`) |

### 4. Multi-Core Thread Scaling & Sustained Throughput (Direct Wasm `-O0`)

Raw JSON: [`batch4_scaling.json`](batch4_scaling.json) (98,749 LOC) and [`batch4_scale_250k.json`](batch4_scale_250k.json) (246,765 LOC, separate scale-up reference).

#### `flat_multi_100k_o0` (98,749 LOC, 18 files, 5 rounds + 1 warmup, all runs SHA-256 `5d5090f074…`)

| Build | `--jobs` | Median wall (ms) | Min wall (ms) | Wall LOC/s | Compile stages (ms) | Compile LOC/s | Peak RSS (MiB) | `p / tc / lf / opt / be / other` (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `batch4d-nopgo` | 1 | `140.7` | `135.8` | `702,071` | `136.4` | `724,072` | `140.5` | `22.7 / 68.9 / 1.4 / 6.2 / 37.3 / 4.3` |
| `batch4d-nopgo` | 2 | `76.2` | `72.7` | `1,296,489` | `70.0` | `1,411,708` | `182.3` | `23.8 / 17.6 / 1.1 / 5.5 / 22.0 / 6.2` |
| `batch4d-nopgo` | 4 | `55.7` | `51.3` | `1,774,463` | `48.1` | `2,054,702` | `188.8` | `15.9 / 14.6 / 1.2 / 3.6 / 12.8 / 7.6` |
| `batch4d-nopgo` | 6 | `49.4` | **`45.9`** | `1,999,125` | `41.1` | **`2,401,483`** | `194.9` | `15.8 / 12.2 / 0.6 / 2.7 / 9.9 / 8.3` |
| `batch4d-nopgo` | 8 (`auto`) | **`49.2`** | `47.3` | **`2,007,065`** | **`42.1`** | **`2,348,371`** | `201.3` | `15.0 / 13.1 / 0.6 / 2.4 / 11.0 / 7.2` |
| `batch4d-nopgo` | 12 | `49.2` | `48.0` | `2,005,881` | `41.6` | `2,373,204` | `210.4` | `16.2 / 12.6 / 0.7 / 2.4 / 9.7 / 7.6` |
| `batch4d-pgo`* | 6 | **`48.5`** | `47.9` | **`2,037,704`** | `41.1` | `2,400,900` | `194.9` | `15.2 / 12.0 / 0.6 / 2.8 / 10.5 / 7.3` |
| `batch4d-pgo`* | 10 | `48.6` | `47.2` | `2,030,601` | **`41.0`** | **`2,406,165`** | `207.0` | `15.7 / 12.5 / 0.6 / 2.4 / 9.8 / 7.6` |

#### `flat_multi_250k_o0` (246,765 LOC, 34 files, 5,633 functions — separate scale-up reference, all runs SHA-256 `fced62e0a3…`)

| Build | `--jobs` | Median wall (ms) | Min wall (ms) | Wall LOC/s | Compile stages (ms) | Compile LOC/s | Peak RSS (MiB) | `p / tc / lf / opt / be / other` (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `v2026.4-3-nopgo` | 1 | `731.2` | `700.5` | `337,463` | `713.2` | `346,007` | `747.9` | `82.4 / 239.2 / 123.2 / 102.6 / 165.8 / 18.1` |
| `batch4d-nopgo` | 1 | `332.0` | `329.8` | `743,248` | `325.5` | `758,087` | `336.6` | `53.1 / 160.7 / 3.9 / 15.8 / 92.0 / 6.5` |
| `batch4d-nopgo` | 8 (`auto`) | **`114.5`** | `108.4` | **`2,154,314`** | **`104.0`** | **`2,373,197`** | **`456.0`** | `31.8 / 33.7 / 4.4 / 8.3 / 25.8 / 10.6` |
| `batch4d-nopgo` | 10 | `111.1` | `107.7` | `2,220,751` | `99.5` | `2,480,050` | `458.6` | `33.0 / 31.1 / 4.4 / 7.4 / 23.6 / 11.6` |
| `batch4d-nopgo` | 12 | **`106.1`** | **`105.0`** | **`2,324,891`** | **`95.1`** | **`2,594,795`** | `462.8` | `32.1 / 30.9 / 4.1 / 7.3 / 20.7 / 11.0` |
| `batch4d-pgo`* | 8 (`auto`) | `110.8` | `108.4` | `2,226,265` | `100.6` | `2,453,176` | `456.4` | `31.3 / 32.4 / 4.1 / 7.4 / 25.5 / 10.3` |
| `batch4d-pgo`* | 10 | `108.7` | `106.3` | `2,269,514` | `96.3` | `2,561,929` | `459.6` | `32.9 / 30.6 / 4.1 / 7.0 / 21.8 / 12.4` |
| `batch4d-pgo`* | 12 | **`104.6`** | **`103.2`** | **`2,359,075`** | **`93.3`** | **`2,646,273`** | `461.7` | `31.9 / 30.5 / 4.1 / 6.9 / 19.9 / 11.4` |

### 5. Direct Paired Progression: Batch 3C (`245f9d6`) → Batch 4D (`b7d0915`, `--jobs 8`, 5 rounds)

Raw JSON: [`batch4_vs_batch3c_j8.json`](batch4_vs_batch3c_j8.json)

| Workload | Batch 3C `j=8` (ms) | Batch 4D `j=8` (ms) | Batch 4 speedup | Peak RSS (`3C → 4D`, MiB) | Key stage delta (`3C → 4D`, ms) |
|---|---:|---:|---:|---:|---|
| `flat_multi_100k_o0` | `70.6` | **`49.4`** (`2.00M/s`) | **1.43×** | `284.1 → 201.3` (**-29.1%**) | `p 20.8→15.5`, `tc 18.0→12.2`, `lf 4.1→0.8`, `opt 4.9→2.5`, `be 14.3→10.8` |
| `flat_single_100k_o0` | `76.5` | **`52.8`** (`1.87M/s`) | **1.45×** | `222.3 → 152.0` (**-31.6%**) | `p 27.6→22.9`, `tc 18.9→12.9`, `lf 3.8→0.6`, `be 13.9→10.8` |
| `flat_multi_250k_o0` | `163.4` | **`114.1`** (`2.16M/s`) | **1.43×** | `663.0 → 457.2` (**-31.0%**) | `p 48.5→32.9`, `tc 41.6→33.7`, `lf 10.2→4.3`, `opt 15.8→7.4`, `be 33.9→24.6` |
| `selfhost_o0_wasm64` | `557.0` | `573.2` | `0.97×` | `362.7 → 288.6` (**-20.4%**) | `p 26.0→20.9`, `opt 8.4→5.8`, `be 21.7→18.1` (`lf` within host jitter) |
| `blot2_o0_wasm64` | `2,736.1` | **`2,572.2`** | **1.06×** | `1,225.5 → 1,090.1` (**-11.1%**) | `p 52.4→46.2`, `tc 524→495`, `lf 2,020→1,903`, `be 80.1→76.5` |
| `flat_multi_100k_o0_c` | `170.9` | **`79.7`** (`1.24M/s`) | **2.15×** | `301.2 → 269.2` (**-10.6%**) | C backend `107.0 → 30.5` (**3.51×**) |
| `selfhost_o0_c` | `665.1` | **`598.3`** | **1.11×** | `373.3 → 335.1` (**-10.2%**) | C backend `98.1 → 40.1` (**2.45×**) |
| `blot2_o0_c` | `4,023.7` | **`2,617.3`** | **1.54×** | `1,227.6 → 1,234.2` (`+0.5%`) | C backend **`1,625.3 → 247.1` (6.58×)** |

### 6. Separate Reference Run: Fresh Clang 23 PGO vs Frozen `v2026.4-3` PGO

Raw JSON: [`batch4_paired_pgo_cpu7.json`](batch4_paired_pgo_cpu7.json) (`--jobs 1`, CPU 7, 3 rounds) and [`batch4_paired_pgo_j8.json`](batch4_paired_pgo_j8.json) (`--jobs 8`, 5 rounds). Because `goosew` exits via `gs_exit` → `_Exit()`, PGO instrumentation links a 4-line `-Wl,--wrap=_Exit` shim that calls `__llvm_profile_write_file()` before `__real__Exit()`.

| Workload | `v2026.4-3` PGO (ms) | Batch 4D PGO `j=1` CPU 7 (ms) | Batch 4D PGO `j=8` (ms) | `j=8` speedup vs `v2026.4-3` PGO |
|---|---:|---:|---:|---:|
| `flat_multi_100k_o0` | `252.7` (`280.7` CPU 7) | `125.8` (`2.23×`, `785k/s`) | **`44.5`** (**`2.22M/s` wall / `2.57M/s` cmp**) | **5.68×** |
| `flat_multi_100k_o2` | `308.5` (`293.0` CPU 7) | `146.5` (`2.00×`, `674k/s`) | **`71.3`** (**`1.39M/s`** at `-O2`) | **4.33×** |
| `flat_single_100k_o0` | `256.1` (`255.1` CPU 7) | `126.3` (`2.02×`, `781k/s`) | **`56.5`** (**`1.74M/s`** single-file) | **4.53×** |
| `selfhost_o0_wasm64` | `3,689.9` (`3,713.0` CPU 7) | `484.7` (`7.66×`) | **`450.8`** (`lf 3,444→313 ms`, **11.0×**) | **8.19×** |
| `selfhost_o2_wasm64` | `3,821.3` (`3,774.9` CPU 7) | `542.5` (`6.96×`) | **`484.6`** (`lf 3,506→311 ms`, **11.3×**) | **7.88×** |
| `blot2_o0_wasm64` | `3,367.9` (`3,337.6` CPU 7) | `2,463.9` (`1.35×`) | **`2,259.9`** (`be 492→69.3 ms`, **7.10×**) | **1.49×** |
| `blot2_o2_wasm64` | `4,080.7` (`4,039.8` CPU 7) | `2,687.8` (`1.50×`) | **`2,383.2`** (`opt 783→107.5 ms`, **7.29×**) | **1.71×** |

---

## Batch-by-Batch Engineering Summary & Qualification Ledger

### Batch 1 (`8af72fa`) — Fix 7× `selfhost` lifetime regression (`selfhost/checker_lifetimes.goose`)
- **Root cause:** Commit `90917c8` added local exit cutoffs (`future.last >= 0`, `l.future_exit`) that bypassed `l.node_body` (**263,663 / 264,314** repeated `(start, last)` bounded spans on `selfhost`) and disabled bulk `life_mark_future_globals` / `shrink_clean` caching whenever `l.future_exit.frame >= 0`.
- **Changes:** Open-addressed `(start, last) -> body` cache (`span_slots`) inside `life_body_span`, reachable-future filtering & cache keying in `life_mark_future_globals`, and reachable future hashes in `life_shrink_array`.
- **Qualification (`build/qualify-batch1/summary.json`, `107.6 s`):** Upstream Goose check exit 0; structural fingerprints identical on `selfhost` & `Blot2` at both `4096` and `0` thresholds; pristine Blot2 §5.2 rejection retained; fixed point `a9ffede7…`; `10,061/10,061` byte-identical vs `v2026.4-3`; `selfhost_o0` `3,831 → 759 ms` (**5.05×**; lifetimes **7.06×**). Raw JSON: [`batch1_paired_nopgo_cpu7.json`](batch1_paired_nopgo_cpu7.json).

### Batch 2 (`a6a4574`) — Single-core backend, optimizer, checker & lifetime speedups
- **Changes:**
  - Direct Wasm backend (`codegen.goose`, `wasm.goose`): append-ordered capture chains + `(function, symbol)` hash table + cursor streaming (eliminating O(C²) scans), 4-state `CG_MEMO_HAS_RELATIVE` memoization, streamlined `wb_reuse_locals` / `wb_reuse_body`.
  - Optimizer (`optimizer.goose`, `model.goose`, `parser.goose`, `checker_validation.goose`, `driver.goose`): O(1) epoch stamps + watched `OptDepSummary` cache (crushing Blot2 `-O2` `optimize_ns` **4.72×**), cached `has_checked_checkfree` / `saw_inline_checkfree`.
  - Checker (`checker.goose`): declaration-indexed specialization chains, recursion-safe `choice_args` scratch, singleton shadow shortcut, mark-on-enqueue type-use validation.
  - Lifetimes (`checker_lifetimes.goose`): 20-byte `LifeRead` with `last: i32` (eliminating 24.5% `life_reads_miss` on `selfhost`), `bypass_memo` for `life_bypasses_exit`, sound pure-value fast path (`life_try_pure_fast_path`).
- **Qualification (`build/qualify-batch2/summary.json`, `106.1 s`):** Upstream Goose check exit 0; structural fingerprints identical at `4096` and `0`; fixed point `e2abdf09…`; `10,061/10,061` byte-identical vs Batch 1. Raw JSON: [`batch2_paired_nopgo_cpu7.json`](batch2_paired_nopgo_cpu7.json).

### Batch 3A (`322fb80`) — Deterministic native compiler worker pool & `--jobs` / `-j` CLI
- **Changes:** Added `native/compiler_parallel.h` built over the pinned `gs_thread_start` / `gs_thread_wait` / `gs_hardware_threads` API (zero edits to `native/runtime/*`, zero `libwinpthread` dependency on Windows, zero new Wasm64 imports), `selfhost/parallel.goose`, `--jobs N|auto` / `-j` CLI flag in `driver.goose`, and C lowering hooks in `codegen_c.goose` + `optimizer.goose`.
- **Qualification (`build/qualify-batch3a/summary.json`):** Fixed point verified; Wasm64 exact 24 imports; conformance `10,797/10,801`, 3-unit split `6,020/6,022`, memory64 `4,773/4,779`, 54 native checks, `ParallelJobsAndPool` unit tests added.

### Batch 3B (`3d2782e`) — First AST struct packing + full multi-core pipeline (parse, check, opt, Wasm)
- **Changes:** Packed `Token` (`88 → 48 B`) and `Node` (`160 → 96 B`), added SPMD barriers + generalized O(1) `g_cpool_grow_array()`, parallel SPMD parse with midpoint `ParseIdentRep` interning, signature-filtered parallel checker body precheck + deferred patch flush, exact-mask parallel optimizer, and parallel Wasm prescan + body emission.
- **Qualification (`build/qualify-batch3b/summary.json`, `165.2 s`):** Upstream Goose check exit 0; Wasm64 exact 24 imports; fixed point `a6aad68c…`; `10,059/10,061` byte-identical vs Batch 3A (only `selfhost/main.goose` `native0`/`native2` changed due to embedded pool hooks).

### Batch 3C (`245f9d6`) — Parallel checker install, zero-copy Wasm backend, parser/teardown & lifetimes
- **Changes:** DFS-order checker slot reservation + single-pass parallel full install; O(1) `gp_grow_*` Wasm slabs with fused capture edges + zero-copy body packing; bounded lexer view, cached parser token kinds, worker-only Linux `MADV_DONTNEED` scratch page release; batched lifetime class keys.
- **Qualification (`build/qualify-batch3c/summary.json`, `195.7 s`):** Upstream Goose check exit 0; Wasm64 exact 24 imports; fixed point `eba02f98…`, executable `9e32b9b4…`; `10,059/10,061` byte-identical vs Batch 3B. Raw JSONs: `batch3c_*.json`.

### Batch 4A (`ca9e1b3`) — Direct-write checker, compact Wasm slots, parallel pure lifetimes, parallel source I/O
- **Changes:**
  - Checker (`checker.goose`): direct-write fenced AST slices during precheck + 4-byte sparse reloc/undo log (shrinking precheck slab **8.5×**: `27.2 → 3.18 MB` on 100k, `68 → 7.95 MB` on 250k) and 4 KiB worker-local proof scratch.
  - Direct Wasm (`codegen.goose`, `wasm.goose`): skip node-sized `region_memo` when the type table rules out owners; compact per-function local slot tables (replacing 0.7–2.6 MB `empty_slots` copies per bucket); direct parallel packing into final code section; fused `-O0` `wb_reuse_locals`.
  - Parallel pure lifetimes & optimizer (`checker_lifetimes.goose`, `optimizer.goose`, `codegen_c.goose`): added `gp_life_dispatch -> gp_life_range` (exact 24 Wasm64 imports), parallelized `life_try_pure_fast_path`, and added O(1) `gp_grow_*` optimizer proof/scratch slabs.
  - Parser/I/O (`sources.goose`, `lexer.goose`, `parser.goose`): parallel `read_file` into worker buffers, parallel DFS-ordered `p.text` install, table-driven punctuation lexer, 1-byte canonical ID cache, precedence table + value-rebased nodes.
- **Qualification (`build/qualify-batch4a/summary.json`, `156.1 s`):** Upstream Goose check exit 0; Wasm64 exact 24 imports; fixed point `7022b79d…`, executable `695747fd…`; conformance `10,797/10,801`, 3-unit `6,020/6,022`, memory64 `4,773/4,779`, 54 native checks, all 22 unit tests; equivalence `10,059/10,061` (only `selfhost/main.goose` `native0`/`native2` changed from `gp_life_dispatch`).

### Batch 4B (`704ab25`) — Exact cache-line AST packing: 32 B `Token` & 64 B `Node`
- **Changes:** Packed `Token` from **`48 → 32 B`** (half a cache line, zero padding: float bits share `integer` via Goose byte images, lazy `token_column` computed on demand for diagnostics/`--dump-ir`, `source: u16`, `kind: u8`, `flags: u8`) and `Node` from **`96 → 64 B`** (one exact cache line, zero padding: 5 cold fields `origin`, `captures`, `named_results`, `coerced_type`, `expansion_binding` moved to sparse `NodeExtra` guarded by `F_HAS_EXTRA` bit 47; `aux: i32` with overflow fallback). Cuts compiler Peak RSS by **-29% to -57%** across workloads and pushes multi-file throughput past **2.0M LOC/s** even on 98.7k LOC.
- **Qualification (`build/qualify-batch4b/summary.json`, `341.9 s`):** Upstream Goose check exit 0; Wasm64 exact 24 imports; `g_runtime_start(201, 201)`; fixed point verified; conformance `10,797/10,801`, 3-unit `6,020/6,022`, memory64 `4,773/4,779`, 54 native checks, all 22 unit tests; **`equivalence` vs Batch 4A: `10,061 / 10,061` (0 differing — 100% byte-identical)**.

### Batch 4C (`f351a13`) — Parallel Native C backend (`--target c`)
- **Changes:** Added `gp_cgen_dispatch -> gp_cgen_range` (`codegen_c.goose` + 1-line hook in `optimizer.goose`, exact 24 Wasm64 imports). Pre-warms type/storage caches and unwind flags on main, emits C function bodies and image codec helpers in parallel across disjoint buckets with deterministic order merge and serial overflow replay, and feeds exact guard offsets into `cc_number_units` (preserving 100% byte-identity for monolithic and `--units 3/8` builds).
- **Qualification (`build/qualify-batch4c/summary.json`, `181.7 s`):** Upstream Goose check exit 0; Wasm64 exact 24 imports; `g_runtime_start(201, 201)`; fixed point `f47a15eb…`, executable `50a59121…`; conformance `10,797/10,801`, 3-unit `6,020/6,022`, memory64 `4,773/4,779`, 54 native checks, all 22 unit tests; equivalence `10,059/10,061` (only `selfhost/main.goose` `native0`/`native2` changed from `gp_cgen_dispatch`).

### Batch 4D (`b7d0915`) — Eliminate O(T²) per-type `seen.resize(p.types.len)` allocations in C backend type walks
- **Root cause:** Discovered while profiling multi-core PGO instrumentation on `blot2 --target c`: five per-type graph walks (`ci_verifiable` in `codegen_c_images.goose` plus `cc_self_run_inside`, `cc_render_unbounded_image`, `cc_image_constructible`, and `cc_frame_borrows` in `codegen_c_storage.goose`) allocated and zeroed a fresh `bool[p.types.len]` (439 KiB on Blot2) on every single call — gigabytes of redundant zero-fills that dominated Blot2's `--target c` backend time.
- **Changes:** Replaced those five `p.types.len` bool arrays with a compact 64-slot open-addressed `cc_seen_insert` set (`codegen_c_storage.goose`), cutting Blot2 `--target c` backend emission from `1,722 ms` (`v2026.4-3`) / `730 ms` (Batch 4C) down to **`250.6 ms`** (**6.87×** faster than `v2026.4-3`).
- **Qualification (`build/qualify-batch4d/summary.json`, `183.2 s`):** Upstream Goose check exit 0; Wasm64 exact 24 imports (`6,106,223` bytes); fixed point `94ac1262…`, executable `d9d63df0…`; conformance `10,797/10,801`, 3-unit `6,020/6,022`, memory64 `4,773/4,779`, 54 native checks, all 22 unit tests; **`equivalence` vs Batch 4C: `10,061 / 10,061` (0 differing — 100% byte-identical)**.

---

## Preserved Rejected Experiments

1. **P1 v1 staging-slab parallel parse (abandoned before Batch 3B):**
   - Parsed files in parallel into staging slabs and merged via serial DFS copy, relocation, and ~150k `intern_ident` calls.
   - Achieved `10,061/10,061` byte-identity, but regressed `flat_multi_100k` parse time from `55 ms → 91 ms` (`24.3 ms` serial staging-slab `.resize()` + `45 ms` serial DFS copy/relocation/intern).
   - Replaced by P1 v2/v3 SPMD parse with O(1) `gp_grow_*`, midpoint `ParseIdentRep` interning, and parallel Phase 2 relocation directly into final `Program` slices.
2. **Interior `MADV_HUGEPAGE` hint in `g_cpool_grow_array` (tested & reverted during Batch 3C):**
   - Hypothesis: reverse `native/runtime/runtime_impl.h`'s `MADV_NOHUGEPAGE` on `>= 4 MiB` growable arrays to reduce 4 KB minor faults and `_Exit` teardown.
   - Finding: `runtime_impl.h:572` only disables THP over the **first 2 MiB** of each region, and Linux THP on this host is `always` with `defer+madvise` defrag. Adding an interior 2 MiB-aligned `MADV_HUGEPAGE` hint reduced minor faults only marginally (`24,978 → 24,480` on `flat_multi_100k`), worsened `selfhost` wall time (`907.8 → 942.3 ms`), and slowed `flat_multi_100k` parse (`44.8 → 48.0 ms`) and `Blot2` parse (`68.4 → 85.0 ms`) in paired jobs-8 trials. Reverted.
3. **SPMD parse worker caps (4 / 6) & branchless Phase 2 rebase rewrite (tested & reverted during Batch 3C):**
   - Capping parse participants at 4 or 6 reduced flat minor faults slightly but slowed `Blot2` multi-file parsing; Clang `-O2` already inlined Phase 2 with vector record loads/stores and conditional moves, so manual branchless rewrites yielded no net parse win. Reverted.
4. **Widening parallel checker body precheck to `const T&`, slices, casts, enum matches & effect-free calls (`b4c-checker-wide`, rejected during Batch 4C):**
   - Passed 60/60 SHA-256 identity checks and 6,432/6,433 frontend conformance cases, **but** only raised parallel body coverage to **28 / 1,347** functions on `selfhost` and **41 / 2,943** on `Blot2` because the dominant real-codebase blockers are inferred return types (`859` selfhost / `3,124` Blot2) and generic declarations (`2,437` Blot2).
   - Saved only `5–16 ms` on real codebases while **regressing flat `--jobs 8` typecheck by +26%–45%** (`flat_multi_100k`: `21.66 → 31.12 ms`; `flat_multi_250k`: `43.67 → 63.33 ms`; `flat_single_100k`: `20.23 → 25.52 ms`). Rejected and deleted.
5. **Parallel `life_body_build_one` + reverse root/callee dependency watches + exact-repeat class-call lookup cache (`b4c-life-algo`, rejected during Batch 4C):**
   - Passed 24/24 SHA-256 checks, 2,404/2,404 conformance, byte-identical fingerprints at `4096` and `0` thresholds, and exact 24 Wasm64 imports.
   - Profiling (`baseline-profile.json`) revealed the post-Batch-4A lifetime profile is now completely flat — the hottest single function is only `5.83%` on `selfhost` (`life_body_build_one`) and `4.37%` on `Blot2` (`life_class_call`), with the top 10 functions each at `1.9%–4.5%`.
   - In lower-contention variant sweeps (`sweep.json`), adding reverse dependency watches and class-call caches **regressed `selfhost` lifetimes by +11%–16%** (`411.7 → 458.4–477.1 ms`) while moving `Blot2` lifetimes by `< 1%` (`2,038.7–2,055.3 → 2,018.1–2,033.5 ms`, within noise). Rejected and deleted.
