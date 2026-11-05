# Goose compiler examples · 2026-11-05

Snapshot 41: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 54.20 | 263.81 | 0.94 | 0.82 |
| tour | 70.84 | 998.44 | 0.93 | 0.94 |
| functions | 150.01 | 1756.74 | 1.13 | 1.00 |
| errors | 88.52 | 843.29 | 0.87 | 0.91 |
| sieve | 84.76 | 420.02 | 2.98 | 2.14 |
| sorting | 144.30 | 2011.94 | 195.75 | 123.41 |
| sudoku | 78.71 | 527.49 | 12.33 | 9.39 |
| maze | 107.49 | 808.27 | 1.07 | 0.98 |
| vm | 86.34 | 744.17 | 1.06 | 0.95 |
| life | 81.10 | 576.08 | 28.06 | 21.70 |

The native column uses this compiler's C backend. Snapshot 40 was measured separately; these runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `7ec5c7ef91e5a157c6a00c8b25d4b037765f485f9f3499c33b3f230206da1e34`. Qualified compiler executable SHA-256: `cef0fa1fafc79501536fc150e1f62ae478b544043b335685610f992f34352ede`. The [summary](summary.json) records cohort results, source, standard library, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/storage-and-captures/summary.json) records partial conformance: 4,914/5,118 passed, 204 failed. Remaining gaps include 38 accepted invalid programs and 166 runtime contracts that fail to compile or execute. Lifetimes, control flow and native image operations remain incomplete.

Snapshot 40 is a [separately collected reference](../names-and-enums/README.md); its 4,798/5,043 passing contracts and 245 failures do not establish snapshot 41 gains. Against snapshot 40, 41 of 5,043 shared checks improved and none regressed. All 75 new source-authored checks passed. The 204 remaining failures comprise 38 invalid-program checks and 166 runtime contracts. No C++ oracle was executed.

An isolated paired fixed-40-source checker guard measured CPU time 40.707 → 41.999 s (+3.17%) and peak memory 491,368 → 492,656 KiB (+0.26%). This is a guard measurement, not an example benchmark win. The [qualification source capsule](../../../../selfhost/results/2026-11-05/storage-and-captures/reproduction.tar.gz) retains the paired checker guard, exact commands and sources.

The snapshot 39 Errors module size cost and snapshot 40 fixture setup verification are retained in the [snapshot 40 record](../names-and-enums/README.md), including its [runner verification](../../../../selfhost/results/2026-11-05/names-and-enums/fixture-setup.json). The same capsule retains rejected aggregate-assignment, stopped-index and captured-state attempts, targeted raw reports and their tradeoffs.
