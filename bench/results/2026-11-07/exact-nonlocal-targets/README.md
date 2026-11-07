# Goose compiler examples · 2026-11-07

Snapshot 48: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 49.10 | 247.34 | 0.83 | 0.77 |
| tour | 61.73 | 884.23 | 0.97 | 0.93 |
| functions | 129.73 | 1588.75 | 1.05 | 0.81 |
| errors | 79.21 | 710.08 | 0.84 | 0.85 |
| sieve | 71.67 | 389.28 | 2.68 | 1.97 |
| sorting | 130.93 | 1803.81 | 179.03 | 113.86 |
| sudoku | 72.86 | 461.55 | 11.49 | 8.86 |
| maze | 86.61 | 712.25 | 1.02 | 0.79 |
| vm | 79.98 | 582.32 | 0.99 | 0.83 |
| life | 74.17 | 514.74 | 26.46 | 20.60 |

The native column uses this compiler's C backend. Sorting's Wasm module is unchanged from snapshot 47; minimal AOT samples ranged 162.2–181.0 ms. Snapshot 47 was measured separately; no matched runtime improvement is established.

Generated compiler C SHA-256: `b8133b5120a3b6a0d393bc260ed2ee8dbf2a880cb3dace8a093e1c03125f3d65`. Qualified compiler executable SHA-256: `10b644041666eddb23349a2eb50efd2da0594113f30fb3516cebcb0dd0d37543`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-07/exact-nonlocal-targets/summary.json) records conformance: 7,003/7,121 passed, 118 failed. Against snapshot 47, 12 of 6,997 shared checks improved and none regressed. All 124 new source-authored checks passed. The 118 remaining failures comprise 6 invalid-program checks and 112 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 2,970/2,970 checks each in Wasmtime and V8; all 1,060 curated native controls also passed. No C++ oracle was executed.

Snapshot 47's [separately collected reference](../../2026-11-07/pending-elements-and-payloads/README.md), at main `79f92914c419c40619a0ca513c158bb5d153b990` (source `e6719a1` plus audit), passed 6,867/6,997 contracts. Its 130 failures comprised 8 accepted invalid programs and 122 runtime contracts rejected by the compiler. Four shared checks improved and all 460 new rows passed. Wasmtime and V8 each passed 2,908 curated Wasm checks, and 998 native controls passed. Cold direct builds took 49.2–130.6 ms and native builds took 248.2–1806.5 ms; sorting took 161.9 ms with minimal AOT and 113.4 ms natively. Separately collected timings do not establish a matched speedup.

For unchanged source and standard library, the errors example emits 17 functions and 45,357 Wasm bytes; snapshot 47 emitted 20 functions and 69,809 bytes.

The capsule retains the previous context-ledger prototypes, source-authored print and namespace fixture corrections, and native result-allocation precision controls. Existing frozen expectations were unchanged. The [snapshot 48 evidence capsule](../../../../selfhost/results/2026-11-07/exact-nonlocal-targets/reproduction.tar.gz) retains sources, commands, guards and rejected attempts.
