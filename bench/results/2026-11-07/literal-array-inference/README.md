# Goose compiler examples · 2026-11-07

Snapshot 52: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 52.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 50.28 | 251.29 | 0.98 | 0.88 |
| tour | 62.20 | 934.88 | 1.08 | 0.98 |
| functions | 132.06 | 1625.22 | 1.14 | 0.97 |
| errors | 80.01 | 722.04 | 1.03 | 1.02 |
| sieve | 72.56 | 405.03 | 2.86 | 2.10 |
| sorting | 133.06 | 1844.22 | 175.00 | 119.54 |
| sudoku | 73.45 | 469.83 | 12.29 | 9.19 |
| maze | 87.43 | 722.98 | 1.11 | 1.00 |
| vm | 81.32 | 592.13 | 1.05 | 1.00 |
| life | 75.71 | 524.30 | 27.85 | 21.80 |

All ten Wasm modules are byte-identical to snapshot 51. Interleaved direct-build ratios for snapshot 52/51 were 0.999–1.005, with a median workload ratio of 1.002. Runtime process cohorts were collected separately; no matched runtime speedup is claimed.

Generated compiler C SHA-256: `11435d57daa506c1e9a161b4c20e9288d47feeb9730e7538bf792bcecc96789f`. Qualified compiler executable SHA-256: `7a2ec7fe06f0c46b79ee298de14c4b207270b2408a883138939258982d84a391`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-07/literal-array-inference/summary.json) records conformance: 7,397/7,503 passed, 106 failed. Against snapshot 51, 2 of 7,435 shared checks improved and none regressed. All 68 new source-authored checks passed. The 106 remaining failures comprise 6 invalid-program checks and 100 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,144/3,144 checks each in Wasmtime and V8; all 1,268 curated native controls also passed.

The [paired build comparison](paired-builds.json) uses both qualified compilers on the same frozen driver, sources and standard library: 100 measured builds plus 20 warmups. The [artifact check](wasm-artifacts.json) pins all ten unchanged Wasm modules.

Concrete generic arguments constrain types before flexible array and fill literals, including nested and control-flow leaves. Floating literal arrays use the existing float-before-integer order. Runtime evaluation order and final fitting and ranking are unchanged; named-literal parameter authority remains separate. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 100 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed.

The capsule preserves authored byte-array rendering mistakes and their results. Revised controls explicitly print numeric elements with independently specified outputs. Named-literal parameter authority remains a separate design, outside this patch. The [snapshot 52 evidence capsule](../../../../selfhost/results/2026-11-07/literal-array-inference/reproduction.tar.gz) retains source, commands, precision guards and rejected attempts. No C++ oracle was executed.
