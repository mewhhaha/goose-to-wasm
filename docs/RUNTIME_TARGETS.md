# Runtime targets

The table is a **historical November 4 reference**, measured with the earlier C++ compiler, not the current Goose compiler. It is useful for the recorded source, workload, toolchain and machine, and does not establish a current native ceiling. Native C executes directly; Wasm candidates use Wasmtime 50's default AOT path. Times are median milliseconds per configured measured iteration count, not per single iteration; ratios in the evidence are paired by confirmation round.


| Workload | Direct Wasm | Selected Wasm | Selected native |
| --- | ---: | ---: | ---: |
| Fannkuch | 1,426 | 1,422 | 1,115 |
| Mandelbrot | 1,062 | 1,060 | 970 |
| Sieve | 784 | 1,528 | 919 |
| CRC32 | 458 | 427 | 207 |
| Custom hash | 280 | 394 | 230 |
| Merge sort | 1,561 | 2,113 | 1,111 |
| Quicksort | 1,499 | 1,435 | 1,252 |
| Life adapter | 50 | 169 | 65 |
| Insertion-sort adapter | 446 | 2,452 | 340 |
| Sudoku adapter | 170 | 178 | 105 |

The fixed selections were built earlier; all executions above were freshly paired in nine rounds on November 4 UTC. The selected Wasm can be an older direct module or a separately built C-to-Wasm or Binaryen artifact. See the [fresh evidence](../bench/results/2026-11-04/leaf-and-loads/README.md) and [original selection](../bench/results/2026-11-02/runtime-targets/README.md). A selected native profile is a workload reference, not a ceiling. For CRC, the native reference uses AVX2 across 32 benchmark repetitions; that difference does not quantify the full gap.

Seven unchanged adapted LangArena ports use their official test and run inputs and warmed timing boundary. Three separate adapters retain original example helper bodies: Life uses a runtime seed on a fixed 64×32 grid for 200 generations; Sorting inserts 20,000 values; Sudoku alternates puzzles. One-time preparation is outside the clock; reset, perturbation, validation and checksum are timed. An opaque iteration barrier prevents dead-code elimination. Nonintrinsic adapter imports disable the direct compiler's closed raw-array proof; only Life and Sorting emit ULEB helpers, and the Sudoku adapter has no resource region versus one in the full program. These are not the full example binaries or their process timings.

Candidates are direct Wasm `-O2`, optional normal Binaryen `-O3`, eight GCC/Clang native profiles (`-O2`/`-O3`, generic/native CPU), and four LLVM C-to-Wasm profiles (`-O2`/`-O3`, scalar/SIMD128, LP64 memory64). Goose `-O2` emits native-target C and Wasm-target C once each; profiles reuse the C within their target. Generic CPU uses `-march=x86-64 -mtune=generic`, and native uses `-march=native`. C candidates use a separate translation-unit barrier, no LTO or fast math, and disabled FMA contraction. Builds and AOT preparation precede runtime; timing is pinned to CPU 2 on a shared host. Three pilot rounds select references by median plus MAD; nine fresh confirmation rounds include the fixed selections, generic GCC `-O2` anchor and direct Wasm without reselecting. Build and preparation timings are single-sample diagnostics.
