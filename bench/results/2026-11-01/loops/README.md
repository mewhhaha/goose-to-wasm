# Small-loop measurements — 2026-11-01

Baseline: repository commit `ce282be`. Candidate: unroll literal count loops
of 1–8 iterations with a scalar-local body and a 32-node budget. Calls,
declarations, addresses, references, exits and nested loops retain the existing
lowering. No algorithm, workload input, runner flag or inlining policy changes.
Astra reviewed the eligibility gate at xhigh effort.

AMD Ryzen 7 3800X, 16 logical CPUs, Linux 7.3.0-4-cachyos, shared desktop host.
Node 24.22.1 / V8 13.6.233.17-node.58, Wasmtime 50.0.1, Emscripten 6.0.13.
The compiler uses pinned Goose `2e2bedef5b980bf013cac5aaa0095bfea64e5569`,
built with Clang 23.1.4, CMake 4.4.4 and Ninja 1.13.2.
[Compiler identities](compiler-identities.json) include source and binary hashes.

## Current backend comparison

One fresh cohort uses the current compiler for all three backends. Five
samples per cell, identical adapted sources, official production inputs and
default engine flags. These are not interleaved cross-backend pairs. Six ports
replace growable storage with bounded arrays; direct Wasm uses memory32 and
C-to-Wasm uses memory64. The native reference is repeated in both chart panels.

Complete uncached build medians in milliseconds, including Python startup;
whiskers in the charts and values after ± show MAD. OS caches remain warm.

| Workload | Direct Wasm ms ±MAD | C → Wasm ms ±MAD | C → native ms ±MAD |
| --- | ---: | ---: | ---: |
| Fannkuch | 72.3 ±2.7 | 655.9 ±8.8 | 311.0 ±1.0 |
| Mandelbrot | 85.8 ±10.3 | 642.6 ±9.2 | 301.5 ±10.2 |
| Sieve | 77.3 ±0.8 | 640.8 ±12.3 | 306.5 ±4.8 |
| CRC32 | 73.4 ±3.5 | 660.4 ±32.2 | 285.3 ±14.1 |
| Custom hash | 74.1 ±0.7 | 648.4 ±6.8 | 310.8 ±13.9 |
| Merge sort | 79.2 ±0.9 | 694.7 ±14.6 | 338.9 ±13.1 |
| Quicksort | 75.9 ±1.1 | 664.3 ±11.7 | 289.6 ±4.6 |

Runtime medians in seconds for the configured measured iterations, excluding
preparation, warmups and startup. Raw samples include dispersion and engine
compilation/instantiation times.

| Workload | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime | Native |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fannkuch | 1.374 | 2.333 | 1.438 | 1.574 | 1.393 |
| Mandelbrot | 1.011 | 0.998 | 1.068 | 1.111 | 0.967 |
| Sieve | 13.584 | 6.078 | 1.693 | 5.524 | 0.914 |
| CRC32 | 3.973 | 0.472 | 0.963 | 0.426 | 1.397 |
| Custom hash | 6.124 | 1.154 | 1.501 | 1.023 | 0.633 |
| Merge sort | 2.216 | 1.409 | 2.145 | 2.826 | 1.461 |
| Quicksort | 1.529 | 1.478 | 1.657 | 1.710 | 1.261 |

[Full cohort](cohort.json): all 315 observations passed. Sources, installed
standard library and compiler hashes still match after sampling. Every rebuilt
direct module matches its qualified artifact. [readme.json](readme.json) selects
these summary rows for the charts through [latest.json](../../latest.json); SVG
metadata retains all input hashes.

Reproduce with the pinned toolchain and engines:

```sh
python bench/langarena.py measure --tracks adapted --backends native c-wasm direct \
  --compile-samples 5 --runtime-samples 5 --skip-edits \
  --output-dir build/performance/round2-cohort \
  --machine-label 'AMD Ryzen 7 3800X, shared desktop host'
```

## Paired runtime measurements

Five interleaved baseline/candidate pairs per engine. Goose O2, identical
adapted CRC32 source, memory32, official production parameters, measured
iterations, warmups and checksums. Every sample passes. Times exclude
preparation, warmups and engine startup; MAD is median absolute deviation.

| Engine | Before seconds ±MAD | After seconds ±MAD | Speedup | Paired speedup range |
| --- | ---: | ---: | ---: | ---: |
| V8 | 4.5072 ±0.0911 | 4.1572 ±0.0413 | 1.084× | 1.060–1.092× |
| Wasmtime | 1.0795 ±0.0128 | 0.9952 ±0.0097 | 1.085× | 1.076–1.110× |

The other six workload modules are byte-identical to the baseline;
[artifact-comparison.json](artifact-comparison.json) records all seven hashes.
The unrolled CRC loop has 16 scalar `select` instructions instead of two.
Its module grows from 3,956 to 4,466 bytes (+510, 12.9%); code bytes grow
from 2,728 to 3,238. This is a measured runtime/size tradeoff.

Five interleaved complete uncached CRC32 builds take 85.0 ±3.6 ms before and
90.8 ±4.5 ms after. The emitter median falls from 2.193 to 1.533 ms. Complete
build times include Python startup, and the shared host adds variation. The
underlying Goose process median falls from 15.25 to 13.16 ms; the whole-build
increase does not establish an emitter regression. These samples establish no
compilation-speed improvement. Engine compilation and
instantiation times are retained separately in [paired.json](paired.json).

## Rejected experiments

| Experiment | Measured workload | V8 speedup | Wasmtime speedup |
| --- | --- | ---: | ---: |
| Omit unused ordinal storage | CRC32 | 1.007× | 1.049× |
| Reuse compatible loop counters | Custom hash | 1.026× | 1.039× |

Both use five interleaved pairs. Neither clears the 5% threshold on both
engines, so both were reverted before the unrolling experiment. The combined
counter experiment was qualified on all seven workloads; its single runtime
samples are screening data, not evidence of a repeatable regression or gain.

## Evidence

- [Frozen baseline qualification](baseline.json): 35 checks across all seven workloads.
- [Unrolling qualification](candidate.json): 35 checks across all seven workloads.
- [Paired unrolling runtime/build measurements](paired.json): 20 executions and 10 complete builds.
- [Ordinal qualification](ordinal.json) and [paired measurements](ordinal-paired.json).
- [Counter qualification](counters.json) and [paired hash measurements](counters-paired.json).
- [Exact compiler source patches](source-snapshots.tar.gz): apply to `ce282be`;
  reconstructed header hashes match the recorded compiler inputs.

These paired results measure the change from `ce282be`. Do not multiply them
by the [previous batch's ratios](../runtime/README.md) or compare their absolute
times as if they came from one cohort. Shared-host timing drift is visible.

## Correctness qualification

All gates passed against the final candidate compiler:

| Gate | Result |
| --- | ---: |
| Default O0/O2 native/C-Wasm/direct matrix | 8,870 runtime observations passed |
| Explicit compile refusals | 3 passed |
| Aggregate returns and scalar math extensions | 100 checks passed |
| Sparse static data | 4 tests passed |
| Stable regions and scoped cleanup | 111 tests passed |
| Dynamic storage/lifetime boundaries | 4 tests passed |
| Native compiler sessions and fixture equivalence | 11 tests passed |
| Incremental cache/driver integration | 12 checks passed |
| Capability inventory consistency | 113 entries, 0 errors |

New cases cover binder reads, narrow wrapping, checked overflow, indexed and
captured binders, and fallback for references, calls, declarations, exits and
count boundaries. The oracle and independent expected values agree.

[Qualification summary and source hashes](qualification.json),
[full differential observations](differential.json.gz),
[extension observations](backend-extensions.json), and
[qualification logs](qualification-logs.tar.gz) retain the evidence.
Expected compile refusals remain separate from executed programs.
