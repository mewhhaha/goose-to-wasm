# Goose compiler examples · 2026-11-07

Snapshot 49: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 49.24 | 247.63 | 0.80 | 0.71 |
| tour | 62.33 | 888.15 | 0.89 | 0.90 |
| functions | 129.24 | 1589.59 | 1.05 | 0.80 |
| errors | 78.02 | 710.02 | 0.83 | 0.84 |
| sieve | 71.47 | 388.94 | 2.64 | 1.94 |
| sorting | 130.63 | 1810.75 | 162.32 | 113.66 |
| sudoku | 72.48 | 463.82 | 11.41 | 8.84 |
| maze | 85.92 | 711.07 | 1.04 | 0.91 |
| vm | 79.69 | 584.44 | 0.99 | 0.91 |
| life | 73.69 | 517.17 | 26.50 | 20.66 |

Both targets use this compiler. These fresh process measurements do not establish a runtime speedup against separately collected prior snapshots.

Generated compiler C SHA-256: `6213108e2780136a86f62eda3e06abcd0f74443d8a2f626be3c60be3e1941080`. Qualified compiler executable SHA-256: `9b84b13667239a7e1c57f7b4b768542faff44325edcc2b26e3038d299d2d334b`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-07/value-and-receiver-contracts/summary.json) records conformance: 7,121/7,235 passed, 114 failed. Against snapshot 48, 4 of 7,121 shared checks improved and none regressed. All 114 new source-authored checks passed. The 114 remaining failures comprise 6 invalid-program checks and 108 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,010/3,010 checks each in Wasmtime and V8; all 1,134 curated native controls also passed. No C++ oracle was executed.

Prior snapshots were collected separately and are references, rather than matched measurements.

Multiassignment evaluates the right-hand side once into a hidden tuple, then performs ordinary assignments in sequence; fixed reference results are snapshotted before writes. The native backend admits a bounded self-relative Row array that constructs directly in its receiving region and tracks exact committed bounds. Admission is narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 108 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed.

The capsule retains rejected separate-region staging and receiver-cancellation experiments, their primary-spec corrections, overlap resolution and precision guards. Plain-load and Wasm forwarding work remains separate; no speedup is claimed. The [snapshot 49 evidence capsule](../../../../selfhost/results/2026-11-07/value-and-receiver-contracts/reproduction.tar.gz) retains source, commands, guards and rejected attempts.
