# Goose compiler examples · 2026-11-05

Snapshot 43: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 51.99 | 262.09 | 0.86 | 0.80 |
| tour | 64.47 | 952.94 | 0.99 | 0.91 |
| functions | 137.02 | 1664.38 | 1.10 | 0.85 |
| errors | 92.56 | 851.46 | 0.88 | 0.91 |
| sieve | 75.18 | 411.75 | 2.82 | 2.06 |
| sorting | 141.76 | 1909.18 | 190.66 | 122.04 |
| sudoku | 76.88 | 481.14 | 12.59 | 9.47 |
| maze | 91.88 | 750.11 | 1.06 | 0.96 |
| vm | 85.60 | 606.33 | 1.05 | 0.84 |
| life | 77.68 | 539.64 | 29.01 | 21.81 |

The native column uses this compiler's C backend. Snapshot 42 was measured separately; these runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `b7e770818d22e90feeebe2a3c08a2ca5a458ae7b478b92c22b72a00fb584d1a9`. Qualified compiler executable SHA-256: `c146df18e94032f322f0bf2f393d77814618a6325590c8c7c2743ce3c8cd115e`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/readonly-numbers-and-static-views/summary.json) records partial conformance: 5,511/5,677 passed, 166 failed. Against snapshot 42, 13 of 5,300 shared checks improved and none regressed. All 377 new source-authored checks passed. The 166 remaining failures comprise 28 invalid-program checks and 138 runtime contracts; none failed C compilation or execution. The remaining failures are 28 accepted invalid programs and 138 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. No C++ oracle was executed.

Snapshot 42's [separately collected reference](../match-render-and-views/README.md) passed 5,121/5,300 contracts: 33 invalid programs were accepted and 146 valid runtime contracts were rejected by the compiler. No executed runtime or C compilation checks mismatched. Its timings do not establish a matched speedup.

A separate debug measurement, using Clang `-O0 -g` and the same workload, observed per-worker packet storage of 17,504 → 128 bytes, custom runtime managed allocations of 4 → 0, requested legacy bytes of 17,408 → 0, and initialized regions of 7 → 2. It used four workers and retained static `Slice` descriptor identities. These are custom runtime allocation counts, not all system `malloc` calls; this is not the ten-example benchmark and makes no timing claim. This isolated codec comparison uses the snapshot-42-based component compiler; exact GDB scripts, commands, tool identities and raw observations are in the batch 43 capsule.

A separate matched numeric/identity checker guard measured a 2.13% peak-RSS increase; shared-machine CPU results do not establish a speedup. No CPU win is claimed from noise. The [batch 43 evidence capsule](../../../../selfhost/results/2026-11-05/readonly-numbers-and-static-views/reproduction.tar.gz) retains component scripts, raw data and rejected experiments, including EF's invalid Wasm from an i64 pointer comparison and literal v1's overbroad ban causing comparison, empty-literal and append regressions, plus the required fixture correction. [Prior batch 42 rejections](../../../../selfhost/results/2026-11-05/match-render-and-views/reproduction.tar.gz) remain available. Astra reviewed the composition and initializer order. The retained failed migration run documents seven restored transitive helper files; expected outputs and compiler sources were unchanged.
