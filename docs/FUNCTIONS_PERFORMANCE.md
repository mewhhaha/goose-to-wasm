# Fresh construction performance

The direct backend initializes eligible pure literals directly in their destination instead of staging a fresh fixed value. This applies to exact-type, closed fixed values without owners, in globals and limited local arrays and strings. Recursive default-return context must match.

Functions shrank from 39,702 to 39,363 bytes (0.85%), and static `memory.copy` instructions fell from 267 to 256. Nine of ten examples became smaller; Squares was unchanged. The baseline includes the [earlier call and growth changes](../bench/results/2026-11-03/functions-calls/README.md), measured in a separate cohort.

A focused confirmation used nine paired blocks of 100 `_start` calls per compiler after 50 warmups, in an engine with an 8 MiB global. Wasmtime fell from 0.5468 to 0.1151 ms, a paired 4.717× speedup (MAD 0.243); V8 fell from 0.4532 to 0.1026 ms, 4.396× (MAD 0.074). These are per-call repeated-entry times, excluding compilation, instantiation and process startup; they are not a native comparison. Post-warmup linear memory fell from 16.0625 to 8.0625 MiB; initial memory was 8.0625 MiB in both versions.

Nine paired warmed rounds across ten workloads gave geometric mean baseline/current speedups of 0.997× on Wasmtime (MAD 0.004) and 0.998× on V8 (MAD 0.001), broadly flat. V8 Fannkuch was about 1.7% slower: paired speedup 0.984× (MAD 0.003). A broader all-fixed-local variant was rejected after Wasmtime Fannkuch and Sudoku slowed about 4% and 6.7%; the narrower policy restored their Wasmtime kernel results. Sudoku's changed code placement and Fannkuch's changed register allocation are observations, not proven causes.

The compiler passed 70 focused gates, 9,573 differential executions and 11,484 host replays. [Measurements, identities and retained experiments](../bench/results/2026-11-03/fresh-construction/README.md) record the boundaries and results.
