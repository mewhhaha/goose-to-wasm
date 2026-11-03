# Fresh construction · November 3, 2026

Compiler SHA-256 `a8c5ba4b4838eea0ae747d495394e6fe77dbdc34e476e8d0cadcb7f225c78352` is compared with compiler `353a3f1bd547330c8ecd32e9084ae92d616340f81f83a5cc30f2e657d577652e` on a shared AMD Ryzen 7 3800X. Goose upstream is `2e2bedef5b980bf013cac5aaa0095bfea64e5569`; Wasmtime is 50.0.1 and Node is 24.22.1 / V8 13.6.233.17-node.58. The full native host uses the static SDK; the warmed reference host and Python bindings are separately frozen builds at the same Wasmtime version.

Direct initialization of eligible fresh literals reduced Functions from 39,702 to 39,363 bytes and static `memory.copy` instructions from 267 to 256. Nine of ten examples shrank; Squares was unchanged. The [investigation](../../../../docs/FUNCTIONS_PERFORMANCE.md) describes the constraints and tradeoffs. The [prior calls cohort](../functions-calls/README.md) is a separate compiler comparison.

A [focused confirmation](initialization-confirmation.json) used nine paired blocks of 100 `_start` calls per compiler after 50 warmups, in an engine with an 8 MiB global. Wasmtime fell from 0.5468 to 0.1151 ms, a paired 4.717× speedup (MAD 0.243); V8 fell from 0.4532 to 0.1026 ms, 4.396× (MAD 0.074). These are per-call times excluding compilation, instantiation and process startup; they are not a native comparison. Post-warmup linear memory was 16.0625 → 8.0625 MiB; initial memory was 8.0625 MiB in both versions. The [screen](initialization-screen.json) is separate.

Fresh cohorts cover nine paired warmed rounds across ten workloads on each engine, ten example programs, host process and preparation measurements, and seven adapted LangArena ports. Reference artifacts were built earlier and executed freshly in paired Wasmtime blocks. Warmed geometric mean baseline/current speedups were 0.997× on Wasmtime (MAD 0.004) and 0.998× on V8 (MAD 0.001). V8 Fannkuch was about 1.7% slower, paired 0.984× (MAD 0.003). [Warmed Wasmtime](final-warmed.json) · [Warmed V8](final-v8.json) · [Examples](examples.json) · [Native host](host.json) · [LangArena](cohort.json) · [References](references.json)

A [broader all-fixed-local variant](rejected-warmed.json) was rejected after Wasmtime Fannkuch and Sudoku slowed about 4% and 6.7%; the narrowed policy restored their Wasmtime kernel results. [Static diagnosis](static-diagnosis.json) found changed Sudoku code placement and Fannkuch register allocation; these do not establish a cause. Process launches include startup; ordinary launches include compilation, while precompiled launches exclude preparation. Warmed body and repeated-entry timings use different boundaries.

Qualification passed 70 focused gates, 9,573 differential executions, including 7,656 native comparisons, and 11,484 host replays across 1,574 unique Wasm modules. [Focused qualification](qualification.json) · [Differential](differential.json) · [Host qualification](host-qualification.json) · [Compiler identity](compiler-identity.json) · [Module analysis](module-analysis.json).

Raw logs, source snapshots and measured guests are indexed in `archives.json.gz`. Current archives and explicitly pinned four `functions-calls` and eight `functions-forwarding` archives reuse byte storage; all executions are fresh. `SHA256.json` is the manifest. A failed qualification setup caused by missing `emcc` on PATH is retained separately; the accepted second attempt used the pinned toolchain. Verify from the repository root:

```sh
python -B bench/results/2026-11-03/fresh-construction/reproduction/verify.py
```
