# Runtime targets

These are qualified empirical references for this source, workload, toolchain and machine, not universal ceilings. Native C executes directly; the Wasm candidates use Wasmtime 50's default AOT path. The chart and table use fresh paired rounds for the current compiler against the same frozen reference selections. Times below are median milliseconds per configured measured iteration count, not per single iteration; ratios in the evidence are paired by confirmation round.

| Workload | Direct Wasm | Selected Wasm | Selected native |
| --- | ---: | ---: | ---: |
| Fannkuch | 1,414 | 1,413 | 1,091 |
| Mandelbrot | 1,040 | 1,040 | 946 |
| Sieve | 1,436 | 1,495 | 894 |
| CRC32 | 451 | 416 | 204 |
| Custom hash | 345 | 387 | 227 |
| Merge sort | 2,119 | 2,105 | 1,103 |
| Quicksort | 1,812 | 1,427 | 1,253 |
| Life adapter | 251 | 168 | 65 |
| Insertion-sort adapter | 443 | 2,324 | 342 |
| Sudoku adapter | 171 | 179 | 105 |

The fixed selections were built earlier; all executions above were freshly paired in nine rounds on November 3 UTC. The selected Wasm can be an older direct module or a separately built C-to-Wasm or Binaryen artifact. See the [fresh evidence](../bench/results/2026-11-03/fresh-construction/README.md) and [original selection](../bench/results/2026-11-02/runtime-targets/README.md). A selected native profile is a workload reference, not a ceiling. For CRC, the native reference uses AVX2 across 32 benchmark repetitions; that difference does not quantify the full gap.

Seven unchanged adapted LangArena ports use their official test and run inputs and warmed timing boundary. Three separate adapters retain original example helper bodies: Life uses a runtime seed on a fixed 64×32 grid for 200 generations; Sorting inserts 20,000 values; Sudoku alternates puzzles. One-time preparation is outside the clock; reset, perturbation, validation and checksum are timed. An opaque iteration barrier prevents dead-code elimination. Nonintrinsic adapter imports disable the direct compiler's closed raw-array proof; only Life and Sorting emit ULEB helpers, and the Sudoku adapter has no resource region versus one in the full program. These are not the full example binaries or their process timings.

Candidates are direct Wasm `-O2`, optional normal Binaryen `-O3`, eight GCC/Clang native profiles (`-O2`/`-O3`, generic/native CPU), and four LLVM C-to-Wasm profiles (`-O2`/`-O3`, scalar/SIMD128, LP64 memory64). Goose `-O2` emits native-target C and Wasm-target C once each; profiles reuse the C within their target. Generic CPU uses `-march=x86-64 -mtune=generic`, and native uses `-march=native`. C candidates use a separate translation-unit barrier, no LTO or fast math, and disabled FMA contraction. Builds and AOT preparation precede runtime; timing is pinned to CPU 2 on a shared host. Three pilot rounds select references by median plus MAD; nine fresh confirmation rounds include the fixed selections, generic GCC `-O2` anchor and direct Wasm without reselecting. Build and preparation timings are single-sample diagnostics.
