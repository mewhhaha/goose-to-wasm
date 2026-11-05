# Goose compiler examples · 2026-11-05

Snapshot 39: ten examples, five samples per measured cell and one runtime warmup, on AMD Ryzen 7 3800X pinned to CPU 7. Both targets use the same qualified Goose compiler; native C uses GCC 16.2.1 at O2. Wasmtime 50.0.1 preparation is measured separately. Cold builds include driver startup and C compilation/linking. Runtime covers fresh process launch through exit, including output. Preparation is measured separately and excluded from precompiled runtime. The separately collected host cohort uses the example cohort's artifacts; runtime columns below come from the host cohort.

| Example | Wasm build ms | Native build ms | Minimal AOT process ms | Native process ms |
| --- | ---: | ---: | ---: | ---: |
| squares | 50.864 | 255.378 | 0.947 | 0.855 |
| tour | 62.860 | 965.079 | 0.978 | 0.910 |
| functions | 136.230 | 1582.418 | 1.114 | 0.833 |
| errors | 84.543 | 819.541 | 0.867 | 0.891 |
| sieve | 72.871 | 390.158 | 2.725 | 1.362 |
| sorting | 132.069 | 1744.293 | 168.927 | 117.460 |
| sudoku | 77.367 | 492.444 | 11.746 | 8.959 |
| maze | 87.898 | 721.416 | 1.062 | 0.857 |
| vm | 82.896 | 598.021 | 1.060 | 0.890 |
| life | 78.149 | 545.571 | 27.391 | 21.018 |

The native column uses this compiler's C backend. Sorting took 168.9 ms with minimal AOT and 117.5 ms natively. Snapshot 38 was measured separately; these runs do not establish a matched runtime improvement.

Generated compiler C SHA-256: `b840947e3a0b12bdf43f34ed4c7dbaa5a89daaf4f7f43d530703c1aa627e9e0c`. Qualified compiler executable SHA-256: `252a3bd12fc0cec06b151a5756380dd9f083ffe1a0fa0ea4d52e2b5c6bf23421`. The [summary](summary.json) records cohort results, source, standard library, workload, toolchain, engine and artifact identities. [Bootstrap and contract evidence](../../../../selfhost/results/2026-11-05/returns-and-contexts/summary.json) records partial conformance: 4,782/5,043 passed, 261 failed. Remaining gaps include 47 accepted invalid programs and 214 runtime contracts that fail to compile or execute. Variable images, lifetimes and control flow remain incomplete.
