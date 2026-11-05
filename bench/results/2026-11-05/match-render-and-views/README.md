# Goose compiler examples · 2026-11-05

Snapshot 42: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 50.40 | 252.93 | 0.82 | 0.73 |
| tour | 63.83 | 909.93 | 1.02 | 0.91 |
| functions | 132.71 | 1611.87 | 1.10 | 0.84 |
| errors | 84.07 | 811.42 | 0.86 | 0.88 |
| sieve | 75.98 | 398.85 | 2.72 | 1.99 |
| sorting | 132.91 | 1988.92 | 167.89 | 116.96 |
| sudoku | 74.03 | 476.99 | 11.79 | 8.99 |
| maze | 87.45 | 721.34 | 1.07 | 0.84 |
| vm | 86.30 | 600.70 | 1.04 | 0.93 |
| life | 75.25 | 539.22 | 27.00 | 21.04 |

The native column uses this compiler's C backend. Snapshot 41 was measured separately; these runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `6916e27a944d67c6d07a1c39b20382f6209d134ff943c8ed1863de62074f9081`. Qualified compiler executable SHA-256: `6e82bc259a95ac02f017eb78804dc3f9b8be5a758faedcf59bf35940967d3adb`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/match-render-and-views/summary.json) records partial conformance: 5,121/5,300 passed, 179 failed. Against snapshot 41, 25 of 5,118 shared checks improved and none regressed. All 182 new source-authored checks passed. The 179 remaining failures comprise 33 invalid-program checks and 146 runtime contracts; none failed C compilation or execution. The remaining failures are 33 accepted invalid programs and 146 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. No C++ oracle was executed.

Snapshot 41's [separately collected reference](../storage-and-captures/README.md) passed 4,914/5,118 contracts, with 204 failures. Its timings do not establish a matched speedup. The prior record retains inherited costs and rejected experiments.

An isolated fixed-40-source lifetime ABBA qualification control measured CPU time +3.41% and peak RSS +1.96%. It does not measure full-batch performance. The fixed-41 paired EE control was noisy and showed no win. The [qualification source capsule](../../../../selfhost/results/2026-11-05/match-render-and-views/reproduction.tar.gz) retains the paired checker guard, exact commands and sources.

The [evidence capsule](../../../../selfhost/results/2026-11-05/match-render-and-views/reproduction.tar.gz) retains rejected rendering R1, lifetime arena and cost failures, rejected ED summaries, and the source-only Astra composition review. The capsule also retains member-call target controls, source-only Astra review, and exact harness versions; the three-line dependency pinning change preserves all original case data.
