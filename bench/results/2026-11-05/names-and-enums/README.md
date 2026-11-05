# Goose compiler examples · 2026-11-05

Snapshot 40: ten examples, five samples per measured cell and one runtime warmup, on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the same qualified Goose compiler; native C uses GCC 16.2.1 at O2. Wasmtime 50.0.1 preparation is measured separately. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The separately collected host cohort uses the example cohort's artifacts; runtime columns below come from the host cohort.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 49.005 | 241.760 | 0.814 | 0.720 |
| tour | 61.026 | 884.007 | 0.955 | 0.877 |
| functions | 126.061 | 1502.150 | 1.082 | 0.827 |
| errors | 80.814 | 791.383 | 0.843 | 0.856 |
| sieve | 70.235 | 379.609 | 2.656 | 1.347 |
| sorting | 127.358 | 1663.377 | 161.697 | 112.621 |
| sudoku | 71.919 | 453.728 | 11.378 | 8.714 |
| maze | 84.414 | 684.104 | 1.040 | 0.810 |
| vm | 78.856 | 576.761 | 1.015 | 0.793 |
| life | 73.218 | 528.952 | 26.379 | 20.471 |

The native column uses this compiler's C backend. Sorting took 161.7 ms with minimal AOT and 112.6 ms natively. Snapshot 39 was measured separately; these runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `54ca14dd2ce2012c45950fcae3c03c77069e5a909ee30ee238052d2e00346e43`. Qualified compiler executable SHA-256: `89b89d0667c2b92e01f38c29a3e1910d18e5ef7fe4e13c12a6daff1ecce15940`. The [summary](summary.json) records cohort results, source, standard library, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/names-and-enums/summary.json) records partial conformance: 4,798/5,043 passed, 245 failed. Remaining gaps include 41 accepted invalid programs and 204 runtime contracts that fail to compile or execute. Variable images, lifetimes and control flow remain incomplete.

The earlier snapshot 39 target-context correction grew the Errors Wasm module from 45,357 to 69,809 bytes; the other nine example modules were byte-identical. This correctness cost is retained in the measured results.

Local-only test setup now creates 14 fixture entries instead of 3,483. The complete 5,043-row before/after comparison preserved every result; the curated V8 checks also remained 1,952/1,952. [Runner verification](../../../../selfhost/results/2026-11-05/names-and-enums/fixture-setup.json) records coverage; it is not timing evidence.
