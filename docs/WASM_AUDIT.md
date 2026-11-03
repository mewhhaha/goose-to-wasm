# Example Wasm audit

The ten examples have further performance headroom. The [latest campaign](../bench/results/2026-11-02/full-hills/README.md) uses compiler `9bfbd591`; the historical audit below uses compiler `73005d231e1a6e3c380dbe1a9440206198f7ac5eb887a32b784e2f9005586689`. The earlier resource-free-call change shrinks Sudoku from 11,953 to 10,966 bytes; the other nine modules are byte-identical. Its warmed adapter improved 1.066× paired (MAD 0.002); [evidence](../bench/results/2026-11-02/resource-free-calls/README.md) distinguishes the full-example probes. The table below records the preceding native-hills cohort. That frozen compiler adds leaf-frame removal, exact unsigned bit-count recognition, positive power-of-two signed remainder handling, limited literal-divisor call specialization and direct guards in eligible unrolled loops. The prior [raw-image audit](../bench/results/2026-11-02/raw-array-images/README.md) describes its separate specialization.

| Example | Baseline bytes | Frozen cohort bytes |
| --- | ---: | ---: |
| Squares | 1,367 | 1,367 |
| Tour | 40,589 | 40,157 |
| Functions | 55,269 | 55,269 |
| Errors | 27,101 | 26,793 |
| Sieve | 7,410 | 7,410 |
| Sorting | 65,038 | 63,755 |
| Sudoku | 12,415 | 11,953 |
| Maze | 21,474 | 21,740 |
| VM | 29,290 | 29,290 |
| Life | 15,740 | 15,719 |

Sizes are static, not speedups. In the preceding native-hills cohort, fifteen paired entry probes measured Sorting at 93.919 → 80.228 ms on V8 and 86.565 → 66.117 ms on Wasmtime; Sudoku at 18.860 → 8.156 ms and 6.541 → 3.836 ms; Life at 30.570 → 9.103 ms and 24.256 → 12.953 ms. Entry includes initialization, callbacks and possible lazy JIT. Those results and qualification are in the [dated evidence](../bench/results/2026-11-02/native-hills/README.md).

Squares folds to 140; Tour requires general prefix modes. Functions, Errors, VM and Maze contain substantial code where first-call compilation matters; Sieve exercises array loops. Literal printing still allocates scratch space and copies immutable bytes. The [native comparison](NATIVE_PERFORMANCE.md) shows that tuned C leaves a larger gap than generic native `-O2`; further changes need semantic proof and measurement on both engines.

In that cohort’s Wasmtime AOT, generic Life retains two `idiv` fallback sites, while its 12×8 and 64×32 constant kernels have none; Sudoku's bit count has one `popcnt`. Naive eight- and sixteen-copy loops regressed Wasmtime and were rejected. See the [machine-code inspection](../bench/results/2026-11-02/native-hills/machine-code.json) and [unrolling controls](../bench/results/2026-11-02/native-hills/unroll-controls.json).

Tour, Errors and Maze also changed; Squares, Functions, Sieve and VM remained byte-identical. Only the LangArena Quicksort module changed; the other six were identical. The separately collected fresh cohort does not establish a compiler kernel speedup.
