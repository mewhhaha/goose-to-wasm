# Goose compiler examples · 2026-11-07

Snapshot 54: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses gcc 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 51.89 | 250.74 | 0.81 | 0.72 |
| tour | 62.00 | 964.96 | 0.89 | 0.86 |
| functions | 137.47 | 1609.79 | 1.06 | 0.81 |
| errors | 79.21 | 762.83 | 0.86 | 0.84 |
| sieve | 71.77 | 391.93 | 2.73 | 1.97 |
| sorting | 133.16 | 1944.04 | 167.24 | 115.39 |
| sudoku | 78.07 | 477.32 | 11.69 | 8.96 |
| maze | 90.98 | 762.26 | 1.04 | 0.82 |
| vm | 84.40 | 624.82 | 1.00 | 0.79 |
| life | 79.36 | 519.46 | 26.84 | 20.86 |

Paired minimal AOT process ratios versus snapshot 53 ranged 0.984–1.015, with a median workload ratio of 1.002; the native-control median was 1.003. These measurements do not establish a broad runtime speedup.

Generated compiler C SHA-256: `46792d91fb3a7da1d53ce009599a405482c3ceff4df47e74bdc6ff509b5b63f0`. Qualified compiler executable SHA-256: `cd387f7a708d7f2f6bd2e934204da4da9d9466058daab37da08e125d284e7c4f`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-07/temporary-region-retirement/summary.json) records conformance: 7,609/7,711 passed, 102 failed. All 7,595 prior checks retained their outcomes. All 116 new source-authored checks passed; these include bounded-memory contracts rather than recovered original-suite failures. The 102 remaining failures comprise 6 invalid-program checks and 96 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,248/3,248 checks each in Wasmtime and V8; all 1,372 curated native controls also passed.

The [paired process comparison](paired-runtime.json) interleaves exact qualified 53/54 minimal AOT artifacts and native controls on the same engine/host: 200 measured processes plus 40 warmups. [Wasm identities](wasm-artifacts.json), [targeted compile costs](resource-costs.json), [memory observations](resource-memory.json) and [module limits](resource-binaries.json) are recorded separately. Prior snapshot 53 results are separately collected references.

The Wasm backend detects owned call results, constructors and function outputs when selecting the existing admitted region runtime, and restores the transient region count after each global declaration. This does not widen representation admission.

Loop sequence temporaries live for the enclosing statement; binders enter loop scope afterward. Source-copy and escape rules remain in force. Wasm fixed aggregate value results snapshot the final channel rather than retain source aliases; references, slices and construction receivers keep identity. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 96 runtime contracts rejected during Goose compilation. All selected runtime checks that reached execution passed. Repeated 10,000-iteration temporary workloads, including str and to_bytes, now fit the same two-page Wasm limit. Thirty-two scalar startup initializers reuse one region instead of 33; an 8,192-byte main temporary then fits without increasing the limit. The guards also preserve live global owners and views and still reject a live value larger than the limit. Unsupported representations still use fallback paths that may retain temporaries. Across 41 changed small modules in the targeted cohort, emitted size was 0.831–1.815 times baseline and median compile CPU was 1.076 times baseline. The 13 byte-identical controls had a median compile CPU ratio of 0.986. These are targeted costs of the final candidate, separate from the ten-example process comparison.

The capsule preserves the original two-page stress, V1 startup retention, V2 missed builtin demand, V3 discarded-tuple cleanup regression, corrected invalid constant-fill drafts and final resource guards. Newly enabled region modules can grow and compile more slowly. The [snapshot 54 evidence capsule](../../../../selfhost/results/2026-11-07/temporary-region-retirement/reproduction.tar.gz) retains source, commands, resource guards and rejected attempts. No C++ oracle was executed.
