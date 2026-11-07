# Goose compiler examples · 2026-11-07

Snapshot 50: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses GCC 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 52.81 | 264.19 | 0.79 | 0.75 |
| tour | 65.40 | 961.53 | 0.90 | 0.85 |
| functions | 137.57 | 1704.15 | 1.06 | 0.82 |
| errors | 83.96 | 771.06 | 0.83 | 0.85 |
| sieve | 76.56 | 397.30 | 2.71 | 1.97 |
| sorting | 139.13 | 1950.15 | 167.08 | 116.23 |
| sudoku | 77.73 | 494.63 | 11.64 | 9.09 |
| maze | 91.87 | 764.77 | 1.04 | 0.82 |
| vm | 84.74 | 629.61 | 1.03 | 0.82 |
| life | 79.07 | 523.94 | 26.83 | 20.84 |

An interleaved direct-build check gave snapshot 50/49 ratios of 0.993–1.005, with a median workload ratio of 1.000. The higher cold-build numbers in the separate full cohort did not reproduce in that paired check. No matched runtime speedup is claimed.

Generated compiler C SHA-256: `4ee44216acaf19cac7094015a574a354ea90c38a86f381da2417b82b80fd6065`. Qualified compiler executable SHA-256: `dadf054e9784bd3dfea0b4c54263ca7cd8391e7d181515b7fc058a08d300d349`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-07/plain-values-and-forwarded-views/summary.json) records conformance: 7,259/7,371 passed, 112 failed. Against snapshot 49, 2 of 7,235 shared checks improved and none regressed. All 136 new source-authored checks passed. The 112 remaining failures comprise 6 invalid-program checks and 106 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,078/3,078 checks each in Wasmtime and V8; all 1,202 curated native controls also passed.

The full cohorts were collected separately. The [paired build check](paired-builds.json) interleaves both qualified compilers on the same frozen driver, workload and standard library: 100 measured builds plus 20 warmups, with source and tool identities pinned.

Owned value copies drop top-level const; references and slice contents keep their access rules. Array-to-slice conversion now carries the pointer and logical length through forwarded tuples. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 106 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed.

The capsule retains rejected const-load variants that overrestricted field assignment or lost read-only borrow authority, and unchanged forwarding mismatches that exposed the missing Wasm conversion. Frozen expectations were preserved. The [snapshot 50 evidence capsule](../../../../selfhost/results/2026-11-07/plain-values-and-forwarded-views/reproduction.tar.gz) retains sources, commands, precision guards and rejected attempts. No C++ oracle was executed.
