# Functions performance · November 3, 2026

Compiler SHA-256 `5e3b87720d24f3285a5f9df57989c200bf7152a28f296cfd3af0220db1cc2edf` is compared with the earlier `9bfbd591` compiler on a shared AMD Ryzen 7 3800X. Goose upstream is `2e2bedef5b980bf013cac5aaa0095bfea64e5569`; Wasmtime is 50.0.1 and Node is 24.22.1 / V8 13.6.233.17-node.58. The full native host uses the static SDK, while the warmed reference host and Python bindings are separately frozen builds at the same Wasmtime version.

The fresh cohorts cover nine paired warmed rounds across ten workloads on each engine, ten example programs, host process and preparation measurements, and seven adapted LangArena ports. Reference artifacts were built earlier and executed freshly in paired Wasmtime blocks. Process, first-entry, preparation and warmed timings are different boundaries.

[Warmed Wasmtime](final-warmed.json) · [Warmed V8](final-v8.json) · [Examples](examples.json) · [Native host](host.json) · [LangArena](cohort.json)

The [post-qualification 31-pair CPU 2 holdout](functions-holdout.json) measured V8 first entry at 7.226 → 5.856 ms (1.220×, MAD 0.045), including lazy JIT, and Wasmtime compile/instantiate at 36.700 → 36.141 ms (1.018×, MAD 0.007). Normal-pool process timing was noisy. The [Functions investigation](../../../../docs/FUNCTIONS_PERFORMANCE.md) describes the code-size change, qualification, rejected alternatives and limitations. The [earlier campaign](../../2026-11-02/full-hills/README.md) is a separate cohort.
