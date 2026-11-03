# Performance campaign

The Astra xhigh plan identifies 24 finite families. The 24 dispositions are 13 kept, seven rejected, three proof-limited and one reference-only. This measured campaign is not a universal optimum claim. Baseline: commit `5706abf`, compiler SHA-256 `73005d231e1a6e3c380dbe1a9440206198f7ac5eb887a32b784e2f9005586689`, host `e046`, 671 source files. The [dated evidence](../bench/results/2026-11-02/full-hills/README.md) pins inputs, compiler, workload and engine. The delivered compiler SHA-256 is `9bfbd591fe0785bfa5d9eedaabf04d1620cc9d23fcf5b3b36539e68858456d46`. The tracker below records the final dispositions; the archived planning JSON is a historical snapshot.

Build and correctness qualification preceded timing. The compiler passed 65 focused gates, 9,573 differential executions and 11,484 host replay executions. Rejected variants and their tradeoffs are retained.

| Hill | Family | Disposition and evidence |
| --- | --- | --- |
| H01 | Static host | Full-SDK static C++ host integrated (`40bb4d…`); 15 paired runs: geometric mean 1.508× direct AOT and 1.443× C-Wasm AOT, with per-example ranges 1.024–1.857× and 1.009–1.704×. Default full SDK retains ordinary and AOT execution. Runtime-only source build took 169.8 s and failed to show a broad shared startup gain; optional static C++ had regressions. See `host-static-final/` and `runtime-only-confirm/`. |
| H02 | Direct import binding | Rejected: no useful broad process-time gain in screens and holdout. |
| H03 | Callback copies and memory lookup | Rejected: cold screens did not justify added code; callback-heavy throughput remains open. |
| H04 | Typed unchecked callbacks | Rejected: ABI tests passed but the nine-round process screen gained only 1.018× AOT. |
| H05 | Host flags and LTO | Rejected: no compelling broad gain; retain portable O2. |
| H06 | Engine initialization controls | Rejected: no-COW and reservation screens were unchanged or weak; altered AOT tunables were incompatible. |
| H07 | Unused loop ordinals | Kept for size; see `ordinal-pairs/`. |
| H08 | Redundant zero stores | Kept; targeted qualification passed. |
| H09 | Print snapshots and scratch bookkeeping | Proof-limited: callback reentry and mutable Text snapshots prevent the proposed shortcut; permanent regression test retained. |
| H10 | Wider fills and bounded copies | Kept with checked scalar fallbacks and a 64-byte minimum for copies. Synthetic 128 MiB per call u32 views: Wasmtime fill 10.87× (MAD 0.134), copy 11.16× (MAD 0.31); V8 fill 11.06× (MAD 0.45), copy 7.31× (MAD 1.37). These are mechanism probes, not examples. See `bulk-mechanism/`. |
| H11 | Literal-range unrolling | Warmed Life 1.747× baseline, MAD 0.0206; see `life-warmed/`. |
| H12 | Descending-loop guard | Kept grouped guard and peeled-eight SIMD; unpeeled-four ordered regression rejected. Early-stop and peeled-four alternatives were not measured. Earlier grouped-guard Sorting was 1.332× (15 pairs, MAD 0.007), Sudoku 1.051× (nine pairs, MAD 0.005); see `sorting-warmed/` and `sort-sudoku-warmed/`. |
| H13 | Tiny popcount and expression calls | Kept; warmed Sudoku adds 1.086×, MAD 0.006; H12+H13 combined 1.141× over nine pairs. See `popcount-pairs/`. |
| H14 | Deferred hash lane write-back | Standalone scalar approach rejected: H13/H14 0.936×, about 7% slower. Deferral is retained only for guarded H15 SIMD; unsupported bodies keep write-through. See `hash-warmed/` and static review. |
| H15 | Blocked hash SIMD | Kept: Wasmtime nine-pair warmed confirmation 2.890× over H13, MAD 0.0159; delivered baseline/final hash was 2.786× Wasmtime and 3.637× V8 in fresh nine-pair cohorts. See `hash-warmed/` and `hash-v8-screen/`. |
| H16 | Affine Life stencil SIMD | Proof-limited: generic stencil extraction is not implemented. A safe future matcher needs purity, alias, overflow, physical-span and toroidal-boundary guards; this does not rule out guarded SIMD. See static review. |
| H17 | Packed CRC basis terms | Rejected and reverted: 15-pair warmed speedup 0.682× Wasmtime (MAD 0.001), 0.712× V8 (MAD 0.002). Correctness passed, but extraction cost lost to selects. See `compiler-experiments/packed-crc-pairs/decision.json`. |
| H18 | Binaryen pass isolation | Reference only: earlier nine-round all-workload sweep found O3 Life 1.82× and local passes 1.338×; O3 regressed Sieve, Fannkuch, Mandelbrot, Sorting and Sudoku. A 15-pair Life confirmation on the delivered compiler found 1.84×. No default pipeline added. |
| H19 | Conditional block bookkeeping | Kept: conservative region-watermark gate qualified; O2 Life hot InlineBlock remains excluded by the proof. No independent speedup claimed. |
| H20 | Private array relayout | Proof-limited: broad physical relayout conflicts with exported-memory and packed-layout contract; narrow computational caching remains possible. See static review. |
| H21 | Sparse static reservations | Synthetic 256 MiB logical global: 184.862 → 2.599 ms and 519.62 → 26.27 MiB RSS, identical Wasm. Peak child RSS comes from `os.wait4` and includes a pre-execution Python memory floor. See `sparse-scaling/`. |
| H22 | Build invocation overhead | 15-sample medians, fresh Python / native CLI / existing worker: Squares 59.8 / 2.16 / 1.58 ms; Life 66.6 / 9.58 / 7.03 ms. Kept: avoid unused dependency hashes when validation/cache is disabled; no headline timing win or new daemon/cache. See `driver-measure/`. |
| H23 | Qualification iteration costs | Kept: collect Python host metadata only when requested. Fifteen CPU 2 pairs: 1.184× without timing (MAD 0.012), 1.0× with timing; ordinary-affinity screen noisy. See `python-metadata-cpu2/`. |
| H24 | V8 first-call code shape | Kept: exact integer-literal-arm select qualified within the measured batch; no independent speedup claimed. |

The delivered compiler's fresh nine-pair warmed baseline/final speedups were Life 1.797×, Sorting 5.203×, hash 2.786× and Sudoku 1.128× on Wasmtime; V8 gave 1.163×, 5.386×, 3.637× and 1.065× respectively. Wasmtime Quicksort, Merge and CRC regressed in this cohort (0.985×, 0.973× and 0.981×). A separate 15-pair Wasmtime Fannkuch check showed a 0.4% cost with outliers. Reports retain the paired samples and controls.

The selected native CRC uses AVX2 across 32 benchmark repetitions (four groups of eight lanes), not adjacent bytes. This difference does not quantify the entire gap; see `reviews/crc-native-vectorization.json` in the evidence.

The campaign started November 2 UTC; fresh V8 and process cohorts finished November 3 UTC. Reference artifacts were built earlier, with fresh execution in paired blocks. The static host and Python bindings both use Wasmtime 50.0.1 but different library bytes.
