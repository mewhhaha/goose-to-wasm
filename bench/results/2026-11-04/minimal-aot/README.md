# Minimal AOT host: November 4, 2026

On a shared AMD Ryzen 7 3800X, a 61-round matched Functions comparison measured 1.002 ms for the previous full host, 0.772 ms for the minimal AOT host, and 0.666 ms for native C. The median paired minimal/full ratio was 0.764 (23.6% lower); minimal/native was 1.158 (15.8% higher). The 95% intervals were 0.757–0.779 and 1.150–1.168, respectively; the full-host A/A ratio was 0.994 (95% interval 0.982–1.011). A CPU 2 diagnostic measured minimal/native 1.227. These are fresh-process launch-to-exit times; AOT preparation is excluded.

The broader 15-sample cohort measured the following direct Wasm and native C process medians, in milliseconds. It is a separate cohort from the paired comparison above.

| Example | Cold | Full AOT | Minimal AOT | Native C |
| --- | ---: | ---: | ---: | ---: |
| Squares | 3.667 | 1.339 | 0.961 | 0.821 |
| Tour | 34.745 | 1.764 | 1.324 | 1.257 |
| Functions | 18.321 | 1.853 | 1.384 | 0.947 |
| Errors | 10.074 | 1.829 | 1.337 | 1.232 |
| Sieve | 8.350 | 2.266 | 1.971 | 1.478 |
| Sorting | 32.385 | 15.542 | 15.727 | 45.734 |
| Sudoku | 8.783 | 4.020 | 4.861 | 4.183 |
| Maze | 11.283 | 1.694 | 1.258 | 1.089 |
| VM | 15.501 | 1.906 | 1.159 | 1.219 |
| Life | 14.437 | 2.813 | 2.821 | 18.770 |

The broad cohort's Functions minimal/native ratio is approximately 1.46. Each runtime cell has one warmup and 15 samples with checked output; five separate preparation samples per artifact and configuration include compilation, serialization and file writing. The build cohort uses five complete uncached builds per cell; the lifecycle cohort uses 15 samples and distinguishes fresh processes from a resident worker with a fresh store and instance per request. The [host report](host.json), [example report](examples.json), [lifecycle report](lifecycle.json) and [paired report](functions-paired.json) retain raw samples, identities and methods.

The full and minimal hosts measure 22,029,544 and 1,412,248 bytes respectively. Minimal AOT supports numeric and linear-memory modules, including SIMD, tail calls, memory64, bulk memory and multivalue; it excludes GC, reference and function reference types, exceptions, components, concurrency and JIT. Artifacts require the matching profile and must be trusted. All ten direct and C-to-Wasm example artifacts passed under the minimal profile. Some C-to-Wasm corpus artifacts use exception handling and are refused by that profile; an all-backend attempt was interrupted by a filesystem failure and is not a passing census.

The historical 1.691 ms Functions host measurement used Python's timed wait, which imposed an approximately 1 ms polling artifact on this system. The corrected harness uses pidfd, so the historical-to-current change includes the method correction. The matched comparison above uses the corrected method on both sides. Lifecycle already used blocking waits.

The compiler SHA-256 was `8c09c1a6bcc782de5b86dda621a91ae234acba8fbe108d146582113eb6a110b6`, unchanged from the separately collected LangArena and runtime-target measurements. Goose revision was `2e2bedef5b980bf013cac5aaa0095bfea64e5569`; engines were Wasmtime 50.0.1 and Node 24.22.1 / V8 13.6.233.17-node.58, with Emscripten 6.0.13 and GCC 16.2.1. The previous 9,573 differential executions were verified and reused; fresh qualification passed 11,484 full-host replays, 1,914 direct minimal-host replays and 78 unit checks. [Qualification](qualification.json) and [execution record](delivery-execution.json) retain the details.

A compiler projection removed 56 copies and 921 Wasm bytes but did not measurably improve runtime, so it was rejected. Lazy input v3 was also rejected after the primary workload remained flat.
