# Goose compiler examples · 2026-11-05

Snapshot 38: ten examples, five samples per measured cell and 1 runtime warmup(s), on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the same qualified Goose compiler; native C uses GCC 16.2.1 at O2. Wasmtime 50.0.1 preparation is measured separately. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The separately collected host cohort uses the example cohort's artifacts; runtime columns below come from the host cohort.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 49.868 | 246.424 | 0.812 | 0.733 |
| tour | 62.015 | 893.985 | 0.947 | 0.900 |
| functions | 127.857 | 1523.215 | 1.061 | 0.818 |
| errors | 77.476 | 712.534 | 0.845 | 0.859 |
| sieve | 72.255 | 382.594 | 2.644 | 1.350 |
| sorting | 129.158 | 1696.557 | 163.744 | 113.491 |
| sudoku | 72.101 | 459.664 | 11.540 | 8.740 |
| maze | 85.623 | 692.626 | 1.056 | 0.912 |
| vm | 79.683 | 584.061 | 1.006 | 0.803 |
| life | 73.875 | 544.492 | 26.604 | 20.779 |

The native column uses this compiler's C backend. Sorting took 163.7 ms with minimal AOT and 113.5 ms natively. Snapshot 37 was measured separately; these runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `75453510d74da0fce4d2b2acca7e3157c7833e01b1d5acbee712f08efa3fc8a3`. Qualified compiler executable SHA-256: `46a68ed99cb3f01ce0cf642666ea88888f3552f3dbad990e9e097cbabf30df51`. The [summary](summary.json) records cohort results, source, standard library, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/flow-and-copying/summary.json) records partial conformance: 4,772/5,043 passed, 271 failed. Remaining gaps include 47 accepted invalid programs and 224 runtime contracts that fail to compile or execute. Variable images, lifetimes and control flow remain incomplete.

A matched compiler self-check recorded 12.3% more peak memory for the corrected loop-flow capture; its single-pair CPU timing is a cost guard, not a performance ranking. The initial broader capture used about 20% more memory. The rejected array-inference-only patch accepted an invalid recursive temporary; the delivered patch tracks copied argument temporaries. [Qualification and tradeoffs](../../../../selfhost/results/2026-11-05/flow-and-copying/summary.json)
