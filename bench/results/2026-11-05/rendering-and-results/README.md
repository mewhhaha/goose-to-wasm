# Goose compiler examples · 2026-11-05

Snapshot 37: ten examples, five samples per measured cell and one runtime warmup, on an AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the same qualified Goose compiler: direct Wasm and native C compiled with GCC 16.2.1 at O2. Cold builds include Python driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Wasmtime 50.0.1 preparation is measured separately and excluded from precompiled runtime. The separately collected host cohort uses the example cohort's artifacts; runtime columns below are from the host cohort.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 52.078 | 268.103 | 0.972 | 0.835 |
| tour | 70.187 | 1007.925 | 1.473 | 1.092 |
| functions | 137.062 | 1655.333 | 1.194 | 1.011 |
| errors | 81.526 | 843.723 | 1.359 | 0.937 |
| sieve | 74.896 | 422.254 | 2.879 | 1.488 |
| sorting | 131.440 | 1830.837 | 178.524 | 122.086 |
| sudoku | 76.910 | 497.884 | 12.573 | 9.316 |
| maze | 88.008 | 766.262 | 1.171 | 0.944 |
| vm | 84.359 | 658.958 | 1.058 | 0.973 |
| life | 77.036 | 603.379 | 28.018 | 21.251 |

The native column includes this compiler's C backend overhead. Separately collected snapshot 34 builds took 50.2–126.0 ms direct and 255.9–1,702.4 ms native; snapshot 37 took 52.1–137.1 ms and 268.1–1,830.8 ms. These independently collected reference runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `18abc2ee8d0f77a39dccab2f173b080b0f85e88bdee664a47108e311991da116`. Qualified compiler executable SHA-256: `a89f4c447a7eea5950f510301cac6be0b7c35d37690da9182952cac42d2b0391`. The [summary](summary.json) records cohort results, source, standard library, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/rendering-and-results/summary.json) records the partial conformance result: 4,717/5,028 passed, 311 failed. Remaining gaps include 61 accepted invalid types and 250 runtime contracts that fail to compile or execute, including variable images, varints, lifetimes and default names.
