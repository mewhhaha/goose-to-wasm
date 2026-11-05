# Goose compiler examples · 2026-11-05

Snapshot 45: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 50.37 | 249.44 | 0.82 | 0.73 |
| tour | 62.84 | 897.45 | 0.92 | 0.91 |
| functions | 131.22 | 1594.54 | 1.08 | 0.83 |
| errors | 83.99 | 804.80 | 0.87 | 0.89 |
| sieve | 72.81 | 392.03 | 2.71 | 1.97 |
| sorting | 132.41 | 1823.01 | 163.14 | 113.79 |
| sudoku | 74.41 | 465.83 | 11.49 | 8.83 |
| maze | 87.28 | 715.68 | 1.05 | 0.81 |
| vm | 80.94 | 586.62 | 1.01 | 0.90 |
| life | 75.04 | 519.11 | 26.57 | 20.67 |

The native column uses this compiler's C backend. Snapshot 44 was measured separately; these runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `89feb6d5fba53f3bd2c36f5e00be164a53588856d2dfad8f0f021f647e6edebb`. Qualified compiler executable SHA-256: `45e640b7f929b101de2c4ca2fe8f2299217e91794900afd7f014aaea74bd5783`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/constant-width-and-reference-checks/summary.json) records partial conformance: 6,251/6,389 passed, 138 failed. Against snapshot 44, 8 of 6,061 shared checks improved and none regressed. All 328 new source-authored checks passed. The 138 remaining failures comprise 12 invalid-program checks and 126 runtime contracts; none failed C compilation or execution. The remaining failures are 12 accepted invalid programs and 126 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. No C++ oracle was executed.

Snapshot 44's [separately collected reference](../relative-cells-and-control-values/README.md), at main `efcbc494f60db7a9fabfb5abebd1a491108786e9`, passed 5,915/6,061 contracts. Its 146 failures comprised 18 accepted invalid programs and 128 runtime contracts rejected by the compiler; none failed C compilation or execution. It gained 20 shared checks and passed 384 new rows. Wasmtime and V8 each passed 2,454 curated Wasm checks, and 516 native controls passed. Separately collected timings do not establish a matched speedup.

The capsule retains rejected float-normalization checkpoints and index_of restoration attempts, including nested exits and relative-reference controls. Expected outputs were unchanged. The [snapshot 45 evidence capsule](../../../../selfhost/results/2026-11-05/constant-width-and-reference-checks/reproduction.tar.gz) retains experiment scripts, raw data and rejected attempts.
