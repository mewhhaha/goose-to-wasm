# Runtime targets

These are qualified empirical references for this source, workload, toolchain and machine, not universal ceilings. Native C executes directly; the Wasm candidates use Wasmtime 50's default AOT path. The chart and table use fresh paired rounds for the current compiler against the same frozen reference selections. Times below are median milliseconds per configured measured iteration count, not per single iteration; ratios in the evidence are paired by confirmation round.

| Workload | Direct Wasm | Selected Wasm | Selected native |
| --- | ---: | ---: | ---: |
| Fannkuch | 1,343 | 1,347 | 1,048 |
| Mandelbrot | 995 | 996 | 920 |
| Sieve | 1,430 | 1,427 | 851 |
| CRC32 | 417 | 401 | 197 |
| Custom hash | 901 | 362 | 216 |
| Merge sort | 2,012 | 2,016 | 1,059 |
| Quicksort | 1,773 | 1,368 | 1,182 |
| Life adapter | 435 | 156 | 60 |
| Insertion-sort adapter | 2,147 | 2,111 | 308 |
| Sudoku adapter | 180 | 169 | 100 |

Selected flags are in the [original evidence](../bench/results/2026-11-02/runtime-targets/README.md); [fresh paired samples](../bench/results/2026-11-02/resource-free-calls/README.md) use the same selections. The warmed Sudoku adapter improved 1.066× (paired ratio MAD 0.002); nine other modules were unchanged. Raw direct Wasm itself was selected for Fannkuch, Mandelbrot, Sieve, Merge sort and insertion sort; a self-reference does not prove that no faster Wasm exists. Pilot-selected native is not necessarily fastest in confirmation: in the original cohort, Sieve's generic GCC `-O2` anchor was slightly faster than the selected native profile. Confirmation did not reselect.

Seven unchanged adapted LangArena ports use their official test and run inputs and warmed timing boundary. Three separate adapters retain original example helper bodies: Life uses a runtime seed on a fixed 64×32 grid for 200 generations; Sorting inserts 20,000 values; Sudoku alternates puzzles. One-time preparation is outside the clock; reset, perturbation, validation and checksum are timed. An opaque iteration barrier prevents dead-code elimination. Nonintrinsic adapter imports disable the direct compiler's closed raw-array proof; only Life and Sorting emit ULEB helpers, and the Sudoku adapter has no resource region versus one in the full program. These are not the full example binaries or their process timings.

Candidates are direct Wasm `-O2`, optional normal Binaryen `-O3`, eight GCC/Clang native profiles (`-O2`/`-O3`, generic/native CPU), and four LLVM C-to-Wasm profiles (`-O2`/`-O3`, scalar/SIMD128, LP64 memory64). Goose `-O2` emits native-target C and Wasm-target C once each; profiles reuse the C within their target. Generic CPU uses `-march=x86-64 -mtune=generic`, and native uses `-march=native`. C candidates use a separate translation-unit barrier, no LTO or fast math, and disabled FMA contraction. Builds and AOT preparation precede runtime; timing is pinned to CPU 2 on a shared host. Three pilot rounds select references by median plus MAD; nine fresh confirmation rounds include the fixed selections, generic GCC `-O2` anchor and direct Wasm without reselecting. Build and preparation timings are single-sample diagnostics.
