# Goose compiler examples · 2026-11-07

Snapshot 56: ten examples, Five samples per measured cell and one runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the exact qualified Goose compiler at Goose O2; native C uses gcc 16.2.1 O2. Engines are Wasmtime 50.0.1 and Node 24.22.1. The operating-system page cache is retained. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The compiler, source, standard library, workload and tool identities are pinned in the raw reports. Agents paused expensive work during this shared-machine measurement window.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 50.87 | 263.59 | 0.96 | 0.87 |
| tour | 64.49 | 938.79 | 1.04 | 0.98 |
| functions | 131.62 | 1680.05 | 1.10 | 0.86 |
| errors | 82.88 | 732.28 | 1.03 | 0.92 |
| sieve | 75.00 | 412.60 | 2.79 | 2.01 |
| sorting | 137.18 | 1853.64 | 172.70 | 119.32 |
| sudoku | 78.45 | 490.69 | 12.14 | 9.36 |
| maze | 87.50 | 720.97 | 1.05 | 0.97 |
| vm | 84.07 | 593.36 | 1.09 | 0.97 |
| life | 75.83 | 547.42 | 27.74 | 21.49 |

Paired minimal AOT process ratios versus snapshot 55 ranged 0.930–1.022, with a median workload ratio of 0.988; the native-control median was 0.997. Matched cold direct-build ratios ranged 0.991–1.002, with a median workload ratio of 1.001. All ten Wasm modules are byte-identical. No broad speedup is established.

Generated compiler C SHA-256: `18fb5a123b4299622959748438fefdf4f19ff1edcefe8e9d24dcd7e138b76ade`. Qualified compiler executable SHA-256: `b765aa67b7c00eb3761d9ae6969add66e6f5c2ecaefa24cabae017510abc2435`. The [summary](summary.json) records source, compiler, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-07/lifetime-containment-index/summary.json) records conformance: 7,687/7,787 passed, 100 failed. Against snapshot 55, 0 of 7,779 prior checks improved and none regressed. All 8 new source-authored checks passed. The 100 remaining failures comprise 6 invalid-program checks and 94 runtime contracts; none failed C compilation or execution. The curated Wasm corpus passed 3,286/3,286 checks each in Wasmtime and V8; all 1,410 curated native controls also passed.

The [paired process comparison](paired-runtime.json) interleaves qualified 55/56 minimal AOT artifacts and native controls on the same engine/host: 200 measured processes plus 40 warmups. [Wasm identities](wasm-artifacts.json) record emitted-module equality or differences. The [matched direct-build comparison](paired-build.json) records 100 measured processes plus 20 warmups using one frozen driver/source tree. Prior snapshot 55 timings are separately collected references.

The lifetime checker indexes its containment memo by exact ordered key using bounded bucket heads. It retains the append ledger, answers and miss walk. Lifetime containment memo queries use an exact-key index; cached answers and containment traversal retain the existing contract. On the fixed snapshot 55 compiler workload, native C emission took 64.98 s with the prior compiler and 48.72 s with the index (CPU 64.63 vs 48.47 s). Peak-RSS medians were 602.9 and 602.8 MiB. Emitted C bytes match. These are two measured processes per compiler after one warmup, with alternating order on CPU 7. The common downstream C compilation took 30.05 s and is separate. The index reserves 128–131,072 logical head bytes per lifetime analysis and adds eight logical bytes per memo entry. Initialization and collision-chain lookup remain costs; the measured peak RSS records the full process.

Loop sequence temporaries live for the enclosing statement; binders enter loop scope afterward. Source-copy and escape rules remain in force. Wasm fixed aggregate value results snapshot the final channel rather than retain source aliases; references, slices and construction receivers keep identity. Existing native Row admission remains narrow: arbitrary inter-row links, copied or escaping roots, and partial or nonlocal construction exits remain refused. The remaining failures are 6 accepted invalid programs and 94 runtime contracts rejected during Goose compilation. All selected runtime checks that reached execution passed.

The capsule retains corrected direct-harness initializer ordering and paired default-budget capacity failures. No speedup is inferred from compiler timeouts or failed runs. The [snapshot 56 evidence capsule](../../../../selfhost/results/2026-11-07/lifetime-containment-index/reproduction.tar.gz) retains source, commands, cache guards and matched measurements. No C++ oracle was executed.
