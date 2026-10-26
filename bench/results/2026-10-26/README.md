# Qualification and measurements — 2026-10-26

These records describe the pinned compiler and the available AMD EPYC 9V74 KVM guest (9 logical CPUs, 9.7 GiB RAM). They are a baseline for this backend and workload set, not a whole-language performance guarantee.

## Performance evidence

- [Backend comparison](report.md): complete uncached build times, warmed kernel times, process wall times, output sizes, and interpretation.
- [Raw backend measurements](report.json): every sample, flags, versions, workload and artifact hashes, and checksums.
- [Incremental measurements](incremental.md) and [raw data](incremental.json): raw compiler, wrapper, unchanged cache hits, persistent-server requests, and edited-source builds.

## Correctness evidence

| Qualification | Result | Record |
| --- | ---: | --- |
| Direct/native/C-Wasm differential matrix | 470 execution observations passed, plus 3 expected compile refusals | [differential.json](differential.json) |
| Engine features on V8 and Wasmtime | 9 features × 2 engines passed | [engine-probes.json](engine-probes.json) |
| Retained C-Wasm portability corpus | 194 passed | [oracle-full.json](oracle-full.json) |
| Retained memory64/native comparison | 80 passed | [oracle-memory64.json](oracle-memory64.json) |
| Cache and persistent-server integration | 12 checks passed | [test_incremental.py](../../../tests/test_incremental.py) |

The differential matrix contains 47 runtime cases at O0 and O2, each executed as native C, C-Wasm/V8, C-Wasm/Wasmtime, direct/V8, and direct/Wasmtime. Refusal checks are explicitly separate from successful execution. The final installed direct compiler is identified in [compiler-identity.json](compiler-identity.json).

The retained 194-check oracle run preceded the final direct-only lowering fix and records its own compiler hash. The 80-check memory64 run used the oracle-only build. Their upstream C code generation and checked runtime inputs are the same as the final combined compiler; these runs qualify the C reference path, not direct-backend feature coverage. GitHub Actions rebuilds and reruns all suites against the committed combined compiler.

All runtime comparisons use identical Goose workload source and runtime input across backends. The C paths use `-O2 -fno-strict-aliasing -ffp-contract=off`. Direct emits binary Wasm32; the standalone C reference preserves the LP64 ABI in Wasm memory64. The difference in representations is part of the compared targets.

Edited programs currently rerun the complete frontend and direct emitter. Whole-module cache hits and unchanged function bytecode fingerprints must not be read as incremental semantic compilation. See [the implemented architecture](../../../docs/INCREMENTAL.md).
