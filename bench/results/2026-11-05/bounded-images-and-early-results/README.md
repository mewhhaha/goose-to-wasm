# Goose compiler examples · 2026-11-05

Snapshot 46: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 53.16 | 263.25 | 0.96 | 0.91 |
| tour | 67.23 | 1004.18 | 1.04 | 0.92 |
| functions | 137.97 | 1675.70 | 1.13 | 1.02 |
| errors | 93.19 | 865.14 | 0.89 | 0.92 |
| sieve | 76.61 | 416.92 | 2.95 | 2.08 |
| sorting | 140.39 | 1933.80 | 179.53 | 124.87 |
| sudoku | 78.88 | 498.57 | 12.38 | 9.49 |
| maze | 92.15 | 760.57 | 1.12 | 0.95 |
| vm | 97.11 | 642.44 | 1.03 | 0.97 |
| life | 82.58 | 546.06 | 28.35 | 21.61 |

The native column uses this compiler's C backend. Snapshot 45 was measured separately; sorting took longer in both columns in this run. These runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `4fdbb47e3326835eb7b9fa7e939c84050d57a2e90ff047fc9d7f643c50e3b973`. Qualified compiler executable SHA-256: `c081b77fa243d6a5cf3df7e45146c06e02b0598db268ac015d99022db9d387b9`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/bounded-images-and-early-results/summary.json) records partial conformance: 6,403/6,537 passed, 134 failed. Against snapshot 45, 4 of 6,389 shared checks improved and none regressed. All 148 new source-authored checks passed. The 134 remaining failures comprise 12 invalid-program checks and 122 runtime contracts; none failed C compilation or execution. No C++ oracle was executed.

Snapshot 45's [separately collected reference](../constant-width-and-reference-checks/README.md), at main `beceaa93f725dadecb86f585fbdf2a5fe746eb91`, passed 6,251/6,389 contracts. Its 138 failures comprised 12 accepted invalid programs and 126 runtime contracts rejected by the compiler; none failed C compilation or execution. It gained 8 shared checks and passed 328 new rows. Wasmtime and V8 each passed 2,618 curated Wasm checks, and 680 native controls passed. Separately collected timings do not establish a matched speedup.

The capsule retains the rejected standalone early-block change and relative-image padding, encoded-parameter and rendering defects, along with corrected source-authored controls. Existing frozen expectations were unchanged. The [snapshot 46 evidence capsule](../../../../selfhost/results/2026-11-05/bounded-images-and-early-results/reproduction.tar.gz) retains experiment scripts, raw data and rejected attempts.
