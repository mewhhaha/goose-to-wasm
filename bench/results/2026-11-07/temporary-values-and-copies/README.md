# Goose compiler examples · 2026-11-07

Snapshot 53: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses gcc 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 49.15 | 247.48 | 0.80 | 0.75 |
| tour | 61.53 | 887.51 | 0.90 | 0.85 |
| functions | 129.21 | 1585.44 | 1.06 | 0.80 |
| errors | 78.36 | 712.45 | 0.84 | 0.84 |
| sieve | 71.57 | 389.70 | 2.63 | 1.94 |
| sorting | 130.78 | 1808.85 | 162.62 | 113.73 |
| sudoku | 72.69 | 462.37 | 11.48 | 8.89 |
| maze | 85.99 | 710.80 | 1.04 | 0.80 |
| vm | 79.77 | 582.07 | 0.98 | 0.84 |
| life | 74.29 | 516.14 | 26.47 | 20.56 |

Paired minimal AOT process ratios versus snapshot 52 ranged 0.953–1.027, with a median workload ratio of 0.998; the native-control median was 1.001. No broad runtime speedup is established.

Generated compiler C SHA-256: `a25439f2b0d546555ace11d683b143e23d313394e8fcb160982d7a7e9a0e01b6`. Qualified compiler executable SHA-256: `c7c51ab1fee6c71f84d3b5fb6cbdde2aa6ceb8659ab203c1e52c93ab7d6cc1ad`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-07/temporary-values-and-copies/summary.json) records conformance: 7,493/7,595 passed, 102 failed. Against snapshot 52, 4 of 7,503 shared checks improved and none regressed. All 92 new source-authored checks passed. The 102 remaining failures comprise 6 invalid-program checks and 96 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,190/3,190 checks each in Wasmtime and V8; all 1,314 curated native controls also passed.

The [paired process comparison](paired-runtime.json) interleaves exact qualified 52/53 minimal AOT artifacts and native controls on the same engine/host: 200 measured processes plus 40 warmups. The [Wasm artifact check](wasm-artifacts.json) records six changed and four unchanged modules. Earlier artifacts remain in [snapshot 52 measurements](../literal-array-inference/measurements.tar.gz). The [engine-label correction](../engine-label-correction/README.md) documents the earlier prose-label mistakes in snapshots 51 and 52.

Loop sequence temporaries live for the enclosing statement; binders enter loop scope afterward. Source-copy and escape rules remain in force. Wasm fixed aggregate value results snapshot the final channel rather than retain source aliases; references, slices and construction receivers keep identity. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 96 runtime contracts rejected during Goose compilation. All selected runtime checks that reached execution passed. A separate 10,000-iteration temporary-array stress traps under a two-page Wasmtime limit in both snapshot 52’s by-value variant and snapshot 53. This does not establish reclamation or equal allocation volume.

The capsule retains the rejected first-scope prototype, previously masked source-copy rejections, the portable wrong-result cohort, and exact baseline/candidate low-memory experiment reports. Failed stress runs are not counted as passing functional checks. The [snapshot 53 evidence capsule](../../../../selfhost/results/2026-11-07/temporary-values-and-copies/reproduction.tar.gz) retains source, commands, precision guards, rejected attempts and the unresolved low-memory experiment. No C++ oracle was executed.
