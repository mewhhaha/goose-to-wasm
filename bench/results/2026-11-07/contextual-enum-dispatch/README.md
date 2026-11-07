# Goose compiler examples · 2026-11-07

Snapshot 51: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 51.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 49.26 | 247.88 | 0.80 | 0.71 |
| tour | 61.64 | 888.10 | 0.91 | 0.91 |
| functions | 129.04 | 1588.70 | 1.07 | 0.82 |
| errors | 78.36 | 711.91 | 0.83 | 0.87 |
| sieve | 71.53 | 390.06 | 2.73 | 1.98 |
| sorting | 131.17 | 1820.09 | 172.24 | 116.93 |
| sudoku | 72.58 | 469.74 | 11.73 | 9.09 |
| maze | 86.13 | 712.05 | 1.05 | 0.84 |
| vm | 79.99 | 584.47 | 1.00 | 0.78 |
| life | 74.00 | 516.91 | 27.14 | 21.14 |

Both targets use this compiler. Previous snapshots were collected separately; no matched runtime speedup is claimed.

Generated compiler C SHA-256: `0f2560354854533bd498d6be60deed82752c50b6ef48819c6de9cba28fb8c146`. Qualified compiler executable SHA-256: `e67ea31056553e4d0752fd9ef66ba0a1d6216811d757340c6167f7240ebdd02f`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-07/contextual-enum-dispatch/summary.json) records conformance: 7,327/7,435 passed, 108 failed. Against snapshot 50, 4 of 7,371 shared checks improved and none regressed. All 64 new source-authored checks passed. The 108 remaining failures comprise 6 invalid-program checks and 102 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,110/3,110 checks each in Wasmtime and V8; all 1,234 curated native controls also passed.

Earlier snapshots are separately collected references. Source, compiler and tool identities are pinned in each report.

Enum case dispatch gives IF, MATCH, block and loop arguments the selected borrowing context, keeps const authority and evaluates real arguments once. Overload trials use payload types without inventing temporary storage. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 102 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed.

The capsule retains the first dispatch prototype, whose overload trials incorrectly revisited enum branches as payloads, its pinned trace, and additional by-value payload precision controls. Frozen original expectations were preserved. The [snapshot 51 evidence capsule](../../../../selfhost/results/2026-11-07/contextual-enum-dispatch/reproduction.tar.gz) retains source, commands, precision guards and rejected attempts. No C++ oracle was executed.
