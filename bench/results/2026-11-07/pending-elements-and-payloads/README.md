# Goose compiler examples · 2026-11-07

Snapshot 47: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 49.24 | 248.20 | 0.79 | 0.75 |
| tour | 61.35 | 885.92 | 0.88 | 0.87 |
| functions | 130.29 | 1582.56 | 1.06 | 0.83 |
| errors | 82.21 | 799.51 | 0.84 | 0.84 |
| sieve | 71.51 | 387.22 | 2.61 | 1.94 |
| sorting | 130.60 | 1806.53 | 161.94 | 113.44 |
| sudoku | 72.67 | 460.09 | 11.36 | 8.81 |
| maze | 85.84 | 709.39 | 1.02 | 0.79 |
| vm | 80.59 | 588.83 | 1.00 | 0.84 |
| life | 74.09 | 513.72 | 26.43 | 20.59 |

The native column uses this compiler's C backend. Snapshot 46 was measured separately; these runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `52aa5342f183677c02843a514704107b3ecef2db2a8767b44f25759f33664a53`. Qualified compiler executable SHA-256: `17890c2354938252cbea8015483be24fcf0add3df4b9bae0d04f5ec2d75fc82c`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-07/pending-elements-and-payloads/summary.json) records conformance: 6,867/6,997 passed, 130 failed. Against snapshot 46, 4 of 6,537 shared checks improved and none regressed. All 460 new source-authored checks passed. The 130 remaining failures comprise 8 invalid-program checks and 122 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 2,908/2,908 checks each in Wasmtime and V8; all 998 curated native controls also passed. No C++ oracle was executed.

Snapshot 46's [separately collected reference](../../2026-11-05/bounded-images-and-early-results/README.md), at main `16a9bc16b41c0db89eb694b9522e8c5d782ce3f1`, passed 6,403/6,537 contracts. Its 134 failures comprised 12 accepted invalid programs and 122 runtime contracts rejected by the compiler. Four shared checks improved and 148 new rows passed. Wasmtime and V8 each passed 2,676 curated Wasm checks, and 770 native controls passed. Cold direct builds took 53.2–140.4 ms and native builds took 263.2–1933.8 ms; sorting took 179.5 ms with minimal AOT and 124.9 ms natively. Separately collected timings do not establish a matched speedup.

The capsule retains corrected source-authored indexing and reusable-assignment controls, the independent checker prototypes and the rejected Wasm descriptor/prefix checkpoints. Existing frozen expectations were unchanged. The [snapshot 47 evidence capsule](../../../../selfhost/results/2026-11-07/pending-elements-and-payloads/reproduction.tar.gz) retains source, commands, controls and rejected attempts.
