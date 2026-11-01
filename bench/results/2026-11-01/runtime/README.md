# Runtime optimization measurements — 2026-11-01

Baseline: repository commit `d9a9f90`. Candidate: arithmetic proofs, safe scalar
`select`, and direct scalar writes. The upstream Goose pin and inlining policy
are unchanged. Compiler/source identities are in [compiler-identities.json](compiler-identities.json).

AMD Ryzen 7 3800X, 16 logical CPUs, Linux 7.3.0-4-cachyos, shared desktop host.
Node 24.22.1 / V8 13.6.233.17-node.58, Wasmtime 50.0.1, Emscripten 6.0.13.
The native compiler was built with Clang 23.1.4, CMake 4.4.4 and Ninja 1.13.2.

## Runtime

Five interleaved baseline/candidate pairs per task and engine. Both compile the
same adapted sources at Goose O2 and produce memory32 Wasm. Official production
parameters, iteration counts, warmups and checksums are unchanged. Every sample
passes its official checksum. Times are median seconds for the full configured
measured iterations, excluding preparation, warmups and startup. Speedup is
baseline median divided by candidate median.

| Workload | V8 before → after (s) | Speedup | Wasmtime before → after (s) | Speedup |
| --- | ---: | ---: | ---: | ---: |
| Fannkuch | 1.4039 → 1.3556 | 1.036× | 1.4751 → 1.4397 | 1.025× |
| Mandelbrot | 1.0062 → 1.0066 | 1.000× | 1.0855 → 1.0854 | 1.000× |
| Sieve | 15.0271 → 13.7670 | 1.092× | 1.6805 → 1.6832 | 0.998× |
| CRC32 | 9.7115 → 4.2100 | 2.307× | 4.8749 → 1.0340 | 4.714× |
| Custom hash | 8.9948 → 6.0242 | 1.493× | 2.0179 → 1.4842 | 1.360× |
| Merge sort | 2.2130 → 2.2017 | 1.005× | 2.1327 → 2.1496 | 0.992× |
| Quicksort | 1.5393 → 1.5236 | 1.010× | 1.6641 → 1.7015 | 0.978× |

CRC32 and custom hash improve on both engines. Sieve improves about 8% in
elapsed time on V8 and is effectively unchanged on Wasmtime. The four control
workloads span 0.978–1.036×; no median runtime regression exceeds 3%. These
are local results on seven adapted kernels, not a whole-language guarantee.

## Compilation and artifacts

Five interleaved complete uncached builds per variant and workload. Times include
Python driver startup, the frontend and direct emitter. OS caches remain warm.
MAD is median absolute deviation. Every rebuilt module is byte-identical to its
qualified runtime artifact.

| Workload | Before ms ±MAD | After ms ±MAD | Emitter ms before → after | Module bytes before → after |
| --- | ---: | ---: | ---: | ---: |
| Fannkuch | 75.52 ±2.36 | 72.26 ±1.02 | 0.222 → 0.204 | 4,813 → 4,598 |
| Mandelbrot | 79.07 ±3.95 | 83.67 ±5.07 | 2.794 → 3.406 | 5,460 → 5,194 |
| Sieve | 82.16 ±2.06 | 87.42 ±6.72 | 4.019 → 3.362 | 4,694 → 4,528 |
| CRC32 | 75.77 ±1.09 | 80.71 ±3.54 | 1.485 → 1.541 | 4,056 → 3,956 |
| Custom hash | 81.72 ±3.89 | 78.02 ±2.98 | 1.565 → 1.485 | 6,632 → 6,313 |
| Merge sort | 83.40 ±4.90 | 84.74 ±2.20 | 5.525 → 6.113 | 7,667 → 7,516 |
| Quicksort | 79.14 ±2.26 | 87.82 ±5.28 | 3.758 → 3.656 | 6,537 → 6,337 |

All seven modules shrink. Complete build and emitter timings are mixed; these
samples do not establish a compilation-speed improvement. The larger whole-build
increases include wrapper/startup variation: for example, Quicksort’s raw Goose
process median falls from 13.45 to 13.02 ms while its complete build median rises.
Shared-host noise remains a limitation; raw samples and phase timings are retained.

Engine compilation/instantiation is recorded separately in [paired.json](paired.json).
It is excluded from kernel times and included in retained process wall times.

## Experiments

- Arithmetic alone: custom hash 1.340× on V8 and 1.362× on Wasmtime.
- Arithmetic plus select: CRC32 2.273× on V8 and 4.619× on Wasmtime.
- Retaining repeated loop callees: rejected as the default. It gives V8 sieve
  8.503× but Wasmtime sieve 0.788×, about 27% longer execution. Native/C-Wasm
  policy was unchanged. The final candidate restores the original inlining policy.
- Eager V8 compilation: diagnostic only. The unchanged baseline sieve takes
  15.06/15.78 s by default and 1.77/1.79 s with `--no-liftoff --no-wasm-tier-up`.
  The accepted measurements use default runner flags.

The [plan and tiering analysis](../../../../docs/RUNTIME_PERFORMANCE.md) explain
why the larger V8 gain was rejected. No workload algorithm or storage bound changes.

## Evidence

- [Paired runtime/build measurements](paired.json): 140 runtime observations and 70 complete builds.
- [Baseline comparison against native C and C-Wasm](baseline.json): 315 observations, all passed.
- [Candidate official-profile qualification](candidate.json): 63 observations, all passed.
- [Arithmetic qualification and measurements](arithmetic.json), [paired arithmetic timings](arithmetic-paired.json).
- [Select qualification and measurements](select.json), [paired select timings](select-paired.json).
- [Rejected inlining measurements](inlining.json), [paired inlining timings](inlining-paired.json).
- [Tiering diagnostic](tiering.json).
- [Exact source snapshots](source-snapshots.tar.gz): patches apply to `d9a9f90`; includes
  the original comparison harness used for the independent and rejected experiments.
  The final paired run uses the checked-in `bench/compare_runtime.py`.

## README charts

[readme.json](readme.json) combines the current candidate's five paired samples
with the same-host native/C-Wasm reference samples from [baseline.json](baseline.json).
These backend cohorts were collected separately; they are not interleaved
cross-backend pairs. [Generated-C equivalence](reference-equivalence.json) verifies
that the reference and current compilers emit byte-identical C for all seven
workloads and both C targets. The [chart pointer](../../latest.json) selects
this snapshot; SVG metadata records each input hash.

## Correctness qualification

All gates passed against the final candidate compiler:

| Gate | Result |
| --- | ---: |
| Default O0/O2 native/C-Wasm/direct matrix | 8,630 runtime observations passed |
| Explicit compile refusals | 3 passed |
| Aggregate returns and scalar math extensions | 100 checks passed |
| Sparse static data | 4 tests passed |
| Stable regions and scoped cleanup | 111 tests passed |
| Dynamic storage/lifetime boundaries | 4 tests passed |
| Native compiler sessions and fixture equivalence | 11 tests passed |
| Incremental cache/driver integration | 12 checks passed |
| Capability inventory consistency | 113 entries, 0 errors |

[Qualification summary and source hashes](qualification.json),
[full differential observations](differential.json.gz),
[extension observations](backend-extensions.json), and
[qualification logs](qualification-logs.tar.gz) retain the evidence.
Expected compile refusals remain separate from executed programs.
