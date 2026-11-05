# Goose compiler examples · 2026-11-05

All 410 example observations, 360 host runtime observations and 150 preparation observations passed their output checks. Each measured cell has five samples and one runtime warmup. Runs used an AMD Ryzen 7 3800X pinned to CPU 7.

Both targets use the same qualified Goose compiler snapshot 32. Direct output is Wasm; native output compiles the same frontend’s C with GCC 16.2.1 at O2. Cold builds include Python driver startup and any C compilation/linking. Runtime is fresh process launch through exit, including output. Wasmtime 50.0.1 preparation is measured separately and excluded from precompiled runtime. The separately collected host run uses the example run’s artifacts.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 48.863 | 242.746 | 0.873 | 0.764 |
| tour | 56.637 | 886.558 | 0.877 | 0.864 |
| functions | 117.608 | 1507.176 | 1.063 | 0.793 |
| errors | 74.696 | 703.872 | 0.833 | 0.840 |
| sieve | 67.054 | 379.464 | 2.695 | 1.347 |
| sorting | 119.928 | 1670.877 | 163.815 | 113.912 |
| sudoku | 69.126 | 453.150 | 11.641 | 8.729 |
| maze | 82.137 | 688.419 | 1.047 | 0.881 |
| vm | 76.633 | 576.284 | 1.005 | 0.822 |
| life | 70.786 | 530.689 | 26.517 | 20.647 |

The native column includes this C backend’s overhead and is not an optimized native ceiling. Snapshot 27 was collected separately: its direct builds took 50.407–114.601 ms and native builds 246.964–1,337.321 ms, versus 48.863–119.928 ms and 242.746–1,670.877 ms here. Sorting native took 113.568 ms in the example run; the separately collected snapshot 27 host run took 1,157.237 ms.

A separate matched experiment on the same snapshot 29 C source tested the general access inlining hint with five alternating samples: Sorting fell from 1.192847 s to 0.113465 s, while C build time rose from 1.216 s to 1.576 s. An exploratory three-sample Clang compiler self-check showed no meaningful win (18.713 s to 18.512 s).

The generated compiler C has SHA-256 `2e7807d1540aa8983b6a20169d8839b87e51c73fb8b78eb8663ab6a0a093c2e6`; both benchmark cohorts used the same qualified compiler executable. Source, standard library, workload, engine and artifact hashes are retained in the [summary](summary.json). The [bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/threads-pools-and-contracts/summary.json) records remaining compatibility gaps.

[Example report](examples.json) · [Host report](host.json) · [Measurements and frozen inputs](measurements.tar.gz) · [Previous snapshot](../ordinary-regions/README.md)
