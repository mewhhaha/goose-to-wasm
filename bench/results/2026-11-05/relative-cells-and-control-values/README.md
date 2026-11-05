# Goose compiler examples · 2026-11-05

Snapshot 44: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 49.77 | 249.84 | 0.81 | 0.73 |
| tour | 62.26 | 894.24 | 0.91 | 0.91 |
| functions | 130.42 | 1591.80 | 1.06 | 0.82 |
| errors | 82.76 | 816.44 | 0.84 | 0.87 |
| sieve | 72.35 | 390.35 | 2.65 | 1.96 |
| sorting | 131.70 | 1823.32 | 163.78 | 113.65 |
| sudoku | 73.39 | 463.71 | 11.43 | 8.86 |
| maze | 87.57 | 713.85 | 1.04 | 0.81 |
| vm | 80.51 | 584.50 | 1.00 | 0.80 |
| life | 74.42 | 518.22 | 26.62 | 20.63 |

The native column uses this compiler's C backend. Snapshot 43 was measured separately; these runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `bca2cbad6f35d44b315e2052b1a5dfbe06d2f90bab0d9f2eaa97e7be72486602`. Qualified compiler executable SHA-256: `3130d2f26a8eb028cb192b88e402d30e35318799d0e06e0be811c91d5dcb2e34`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/relative-cells-and-control-values/summary.json) records partial conformance: 5,915/6,061 passed, 146 failed. Against snapshot 43, 20 of 5,677 shared checks improved and none regressed. All 384 new source-authored checks passed. The 146 remaining failures comprise 18 invalid-program checks and 128 runtime contracts; none failed C compilation or execution. The remaining failures are 18 accepted invalid programs and 128 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. No C++ oracle was executed.

Snapshot 43's [separately collected reference](../readonly-numbers-and-static-views/README.md), at main `9efdf93047d4363b2d3163cf59f5c4bc41446524`, passed 5,511/5,677 contracts. Its 166 failures comprised 28 accepted invalid programs and 138 runtime contracts rejected by the compiler; none failed C compilation or execution. Wasmtime and V8 each passed 2,272 curated Wasm checks, and 314 native controls passed. Separately collected timings do not establish a matched speedup.

The capsule retains rejected range and float joins, tail-only inferred results, broad reference guards and the O0 probe stack-limit failure. Exact outputs were unchanged. A separate named-constant f32 widening bug also reproduces on snapshot 43 and remains documented for follow-up. The [snapshot 44 evidence capsule](../../../../selfhost/results/2026-11-05/relative-cells-and-control-values/reproduction.tar.gz) retains experiment scripts, raw data and rejected attempts.
