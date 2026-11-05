# Goose compiler examples · 2026-11-05

All 410 example observations, 360 host runtime observations and 150 preparation observations passed their output checks. Each measured cell has five samples and one runtime warmup. Runs used an AMD Ryzen 7 3800X pinned to CPU 7. Reports use UTC timestamps; this batch was collected overnight on 4–5 November in Stockholm.

Both targets use frozen Goose compiler snapshot 27. Direct output is Wasm; native output compiles the same frontend’s C with GCC 16.2.1 at O2. Cold builds include Python driver startup and any C compilation/linking. Runtime is fresh process launch through exit, including output. Wasmtime 50.0.1 preparation is measured separately and excluded from precompiled runtime. The host run uses the example run’s artifacts and was collected separately.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 50.407 | 246.964 | 0.834 | 0.761 |
| tour | 59.615 | 862.206 | 0.896 | 0.817 |
| functions | 111.214 | 1266.201 | 1.084 | 0.840 |
| errors | 68.684 | 646.172 | 0.856 | 0.825 |
| sieve | 61.493 | 370.786 | 2.739 | 5.663 |
| sorting | 114.601 | 1337.321 | 169.626 | 1157.237 |
| sudoku | 63.969 | 431.533 | 11.868 | 9.665 |
| maze | 75.263 | 588.751 | 1.074 | 0.947 |
| vm | 71.349 | 521.037 | 1.018 | 0.810 |
| life | 64.855 | 479.020 | 27.015 | 21.033 |

The native column includes this C backend’s remaining overhead and is not an optimized native ceiling. Native compilation and small-process startup have regressions against separately collected snapshot 23 runs; those runs are not a paired control. Sorting remains much slower in this C backend than in Wasm.

The generated compiler C has SHA-256 `c3d96198541323e5a137ca611e85cb3bd24b1f39c8012812a95cda4c4d7b0e9b`. Benchmark and full-suite executables were separate builds of those same C bytes with the same Clang flags; both executable identities are recorded in the [summary](summary.json). Source, standard library, workload, engine and artifact hashes are retained. The [bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/regions-and-contracts/summary.json) records unfinished compatibility work.

[Example report](examples.json) · [Host report](host.json) · [Measurements and frozen inputs](measurements.tar.gz) · [Previous snapshot](../../2026-11-04/goose-compiler/README.md)
