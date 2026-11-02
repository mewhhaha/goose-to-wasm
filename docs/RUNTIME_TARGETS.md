# Runtime targets

These are qualified empirical references for this source, workload, toolchain and machine, not universal ceilings. Native C executes directly; the Wasm candidates use Wasmtime 50's default AOT path. The chart compares warmed direct Wasm with pilot-selected Wasm and native references. Times below are median milliseconds per configured measured iteration count, not per single iteration; ratios in the evidence are paired by confirmation round.

| Workload | Direct Wasm | Selected Wasm | Selected native |
| --- | ---: | ---: | ---: |
| Fannkuch | 1,434 | 1,434 | 1,105 |
| Mandelbrot | 1,057 | 1,057 | 960 |
| Sieve | 1,527 | 1,527 | 909 |
| CRC32 | 450 | 418 | 207 |
| Custom hash | 978 | 396 | 231 |
| Merge sort | 2,128 | 2,128 | 1,114 |
| Quicksort | 1,825 | 1,417 | 1,229 |
| Life adapter | 464 | 173 | 65 |
| Insertion-sort adapter | 2,335 | 2,335 | 345 |
| Sudoku adapter | 221 | 182 | 106 |

Selected flags and samples are in the [dated evidence](../bench/results/2026-11-02/runtime-targets/README.md). Raw direct Wasm itself was selected for Fannkuch, Mandelbrot, Sieve, Merge sort and insertion sort; a self-reference does not prove that no faster Wasm exists. Pilot-selected native is not necessarily fastest in confirmation: for Sieve, the generic GCC `-O2` anchor was slightly faster than the selected native profile. Confirmation did not reselect.

Seven unchanged adapted LangArena ports use their official test and run inputs and warmed timing boundary. Three separate adapters retain original example helper bodies: Life uses a runtime seed on a fixed 64×32 grid for 200 generations; Sorting inserts 20,000 values; Sudoku alternates puzzles. One-time preparation is outside the clock; reset, perturbation, validation and checksum are timed. An opaque iteration barrier prevents dead-code elimination. Nonintrinsic adapter imports disable the direct compiler's closed raw-array proof; only Life and Sorting emit ULEB helpers, and the Sudoku adapter has no resource region versus one in the full program. These are not the full example binaries or their process timings.

Candidates are direct Wasm `-O2`, optional normal Binaryen `-O3`, eight GCC/Clang native profiles (`-O2`/`-O3`, generic/native CPU), and four LLVM C-to-Wasm profiles (`-O2`/`-O3`, scalar/SIMD128, LP64 memory64). Goose `-O2` emits native-target C and Wasm-target C once each; profiles reuse the C within their target. Generic CPU uses `-march=x86-64 -mtune=generic`, and native uses `-march=native`. C candidates use a separate translation-unit barrier, no LTO or fast math, and disabled FMA contraction. Builds and AOT preparation precede runtime; timing is pinned to CPU 2 on a shared host. Three pilot rounds select references by median plus MAD; nine fresh confirmation rounds include the fixed selections, generic GCC `-O2` anchor and direct Wasm without reselecting. Build and preparation timings are single-sample diagnostics.
