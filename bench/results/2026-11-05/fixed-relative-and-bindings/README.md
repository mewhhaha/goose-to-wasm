# Goose compiler examples · 2026-11-05

All 410 example observations, 360 host runtime observations and 150 preparation observations passed their output checks. Each measured cell has five samples and one runtime warmup. Runs used an AMD Ryzen 7 3800X pinned to CPU 7.

Both targets use the same qualified Goose compiler snapshot 34. Direct output is Wasm; native output compiles the same frontend’s C with GCC 16.2.1 at O2. Cold builds include Python driver startup and any C compilation/linking. Runtime is fresh process launch through exit, including output. Wasmtime 50.0.1 preparation is measured separately and excluded from precompiled runtime. The separately collected host run uses the example run’s artifacts; the runtime columns below are from the host cohort.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 50.167 | 255.870 | 0.790 | 0.701 |
| tour | 57.877 | 929.981 | 0.887 | 0.824 |
| functions | 124.612 | 1559.155 | 1.065 | 0.796 |
| errors | 78.067 | 716.113 | 0.848 | 0.821 |
| sieve | 69.286 | 388.488 | 2.627 | 1.341 |
| sorting | 126.035 | 1702.367 | 161.956 | 113.175 |
| sudoku | 71.592 | 464.018 | 11.508 | 8.681 |
| maze | 85.048 | 706.429 | 1.042 | 0.806 |
| vm | 79.524 | 588.849 | 0.998 | 0.777 |
| life | 75.966 | 559.946 | 26.463 | 20.609 |

The native column includes this C backend’s overhead and is not an optimized native ceiling. Snapshot 32 was collected separately: its direct builds took 48.863–119.928 ms and native builds 242.746–1,670.877 ms, versus 50.167–126.035 ms and 255.870–1,702.367 ms here. Snapshot 34 focuses on compatibility and C emission correctness; these results do not establish a matched runtime improvement.

The generated compiler C has SHA-256 `f25de953f30c4079fba4df3c8f4aa85a32fc78631857f11fb24da1a793f99af5`. Both cohorts used the exact qualified compiler executable, SHA-256 `33eeddafe7523bfe2b4093debd84b34da3395a1efe83b25a94fbf490bb1c75f1`. Source, standard library, workload, engine and artifact hashes are retained in the [summary](summary.json). The [bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/fixed-relative-and-contracts/summary.json) records remaining compatibility gaps.

[Example report](examples.json) · [Host report](host.json) · [Previous snapshot](../threads-pools-and-access/README.md)
