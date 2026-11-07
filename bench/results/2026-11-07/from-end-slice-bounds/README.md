# Goose compiler examples · 2026-11-07

Snapshot 55: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses gcc 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 57.66 | 287.21 | 0.95 | 0.87 |
| tour | 71.15 | 1096.56 | 1.05 | 0.97 |
| functions | 149.45 | 1939.30 | 1.11 | 0.90 |
| errors | 89.69 | 895.43 | 0.87 | 0.94 |
| sieve | 81.96 | 452.23 | 2.82 | 2.03 |
| sorting | 152.09 | 2217.10 | 197.10 | 124.20 |
| sudoku | 83.31 | 538.21 | 12.66 | 9.51 |
| maze | 102.07 | 845.20 | 1.16 | 0.97 |
| vm | 91.41 | 822.92 | 1.07 | 0.94 |
| life | 85.21 | 680.75 | 28.43 | 21.81 |

Paired minimal AOT process ratios versus snapshot 54 ranged 0.985–1.013, with a median workload ratio of 0.999; the native-control median was 1.001. Matched cold direct-build ratios ranged 0.987–1.005, with a median workload ratio of 0.997. All ten Wasm modules are byte-identical. No broad speedup is established.

Generated compiler C SHA-256: `eb9ba3b7cb5a8be6c29583c32589eb329d1f95283d4debf16cb8341050096499`. Qualified compiler executable SHA-256: `195c1d74e4b6f79829c93be239d3a3c7cf4606fcd8feb13ba14b15a397ce2a26`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-07/from-end-slice-bounds/summary.json) records conformance: 7,679/7,779 passed, 100 failed. Against snapshot 54, 2 of 7,711 prior checks improved and none regressed. All 68 new source-authored checks passed. The 100 remaining failures comprise 6 invalid-program checks and 94 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,282/3,282 checks each in Wasmtime and V8; all 1,406 curated native controls also passed.

The [paired process comparison](paired-runtime.json) interleaves qualified 54/55 minimal AOT artifacts and native controls on the same engine/host: 200 measured processes plus 40 warmups. [Wasm identities](wasm-artifacts.json) record emitted-module equality or differences. The [matched direct-build comparison](paired-build.json) records 100 measured processes plus 20 warmups using one frozen driver/source tree. Prior snapshot 54 timings are separately collected references.

The checker compares raw constant slice bounds for reversed order only when neither endpoint uses `^`. Both backends normalize from-end bounds as `len - k` and retain runtime range checks. From-end slices now use the existing normalized runtime range checks. The complete original parser_all program passes native C at O0/O2; whole-program Wasm emission remains refused by the existing thread ABI boundary, with no partial-source gain claimed.

Loop sequence temporaries live for the enclosing statement; binders enter loop scope afterward. Source-copy and escape rules remain in force. Wasm fixed aggregate value results snapshot the final channel rather than retain source aliases; references, slices and construction receivers keep identity. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 94 runtime contracts rejected during Goose compilation. All selected runtime checks that reached execution passed.

Private whole parser_all Wasm attempts remain refused by the existing thread ABI boundary. The complete original program passes nativeC; no partial-source Wasm gain is claimed. Component55 was first checked against rejected internal54V3; root recomposes only its checker patch on delivered54V4. The [snapshot 55 evidence capsule](../../../../selfhost/results/2026-11-07/from-end-slice-bounds/reproduction.tar.gz) retains source, commands, guards and the separate Wasm admission boundary. No C++ oracle was executed.
