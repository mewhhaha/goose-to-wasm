# Sieve tiering and byte fills — 2026-11-01

Baseline: repository commit `3065a72`. Candidate: retain substantial nested-loop
kernels at repeated call sites, and lower simple byte-fill loops to guarded
`memory.fill`. The policy applies only to direct Wasm. Native/C-Wasm inlining,
workload algorithms, inputs, warmups and runner flags are unchanged.

AMD Ryzen 7 3800X, 16 logical CPUs, Linux 7.3.0-4-cachyos, shared desktop host.
Node 24.22.1 / V8 13.6.233.17-node.58, Wasmtime 50.0.1, Emscripten 6.0.13.
Goose `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, built with Clang 23.1.4,
CMake 4.4.4 and Ninja 1.13.2. [Compiler/source identities](compiler-identities.json).

## Current backend comparison

One fresh cohort measures all three backends with the current compiler, five
samples per cell and identical adapted sources. Six ports replace growable
storage with bounded arrays. Direct Wasm uses memory32; C-to-Wasm uses memory64.
These are not interleaved cross-backend pairs. Native is repeated in both chart
panels. All 315 observations passed; source, library and compiler hashes remain
unchanged, and every rebuilt direct module matches its qualified artifact.

Complete uncached build medians in milliseconds, including Python startup.
Values after ± and chart whiskers show MAD; OS caches remain warm.

| Workload | Direct Wasm ms ±MAD | C → Wasm ms ±MAD | C → native ms ±MAD |
| --- | ---: | ---: | ---: |
| Fannkuch | 72.7 ±2.4 | 675.0 ±7.9 | 309.9 ±3.2 |
| Mandelbrot | 76.4 ±2.8 | 660.5 ±12.2 | 299.0 ±3.2 |
| Sieve | 74.6 ±2.2 | 652.5 ±10.8 | 296.3 ±4.8 |
| CRC32 | 73.1 ±1.3 | 665.3 ±13.5 | 288.4 ±12.9 |
| Custom hash | 79.5 ±2.3 | 650.2 ±18.8 | 320.0 ±15.0 |
| Merge sort | 76.2 ±1.0 | 677.0 ±26.3 | 336.1 ±12.8 |
| Quicksort | 74.7 ±1.2 | 660.8 ±8.4 | 318.3 ±13.0 |

Runtime medians in seconds for the configured measured iterations, excluding
preparation, warmups and startup. Raw samples retain dispersion and engine
compilation/instantiation times.

| Workload | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime | Native |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fannkuch | 1.395 | 2.343 | 1.458 | 1.588 | 1.459 |
| Mandelbrot | 1.017 | 1.033 | 1.076 | 1.160 | 0.978 |
| Sieve | 1.461 | 6.181 | 1.564 | 5.687 | 0.909 |
| CRC32 | 4.046 | 0.480 | 0.965 | 0.431 | 1.405 |
| Custom hash | 6.078 | 1.174 | 1.508 | 1.065 | 0.647 |
| Merge sort | 2.230 | 1.429 | 2.160 | 2.875 | 1.476 |
| Quicksort | 1.623 | 1.503 | 1.693 | 1.769 | 1.257 |

[cohort.json](cohort.json) retains every observation. [readme.json](readme.json)
selects these rows through [latest.json](../../latest.json); SVG metadata retains
the source hashes. Absolute times from different cohorts should not be combined.

Reproduce with the pinned toolchain and engines:

```sh
python bench/langarena.py measure --tracks adapted --backends native c-wasm direct \
  --compile-samples 5 --runtime-samples 5 --skip-edits \
  --output-dir build/performance/sieve-cohort \
  --machine-label 'AMD Ryzen 7 3800X, shared desktop host'
```

## Sieve: paired measurements

Five interleaved baseline/candidate pairs per engine, identical sources at
Goose O2, and memory32 modules rebuilt to match each compiler's qualified
artifact. Every execution passes the
official production checksum. Kernel times exclude preparation, warmups and
engine startup; MAD is median absolute deviation.

| Engine | Before seconds ±MAD | After seconds ±MAD | Speedup | Paired speedup range |
| --- | ---: | ---: | ---: | ---: |
| V8 | 13.5957 ±0.0448 | 1.4466 ±0.0053 | 9.398× | 9.363–9.609× |
| Wasmtime | 1.6936 ±0.0139 | 1.5618 ±0.0106 | 1.084× | 1.075–1.093× |

The module shrinks from 4,528 to 3,655 bytes (−873, 19.3%); code bytes fall
from 3,311 to 2,423. Five paired complete uncached builds take 73.31 ±0.99 ms
before and 71.61 ±0.92 ms after, including Python startup. The emitter median
falls from 3.363 to 2.550 ms. Whole-build time is effectively unchanged.
Engine compilation/instantiation remains separate in [paired.json](paired.json).

## Why V8 was slow

The frontend had inlined warmup and measured kernels into one long `main`
invocation. V8 cannot switch an already-running Wasm function from its baseline
compiler to optimized code, so those internal warmups did not enter a new tier.
See the [V8 compilation pipeline](https://v8.dev/docs/wasm-compilation-pipeline).

A [fresh baseline diagnostic](tiering.json) runs the same immutable module in
13.714 seconds with default V8 and 1.774 seconds with the optimizing compiler
forced on; both checksums pass. These are single diagnostic samples, not the
accepted benchmark mode. All reported comparisons use default engine flags.

## Implementation and controls

The direct-only inlining veto uses the existing optimizer classification walk:
at least 64 nodes, two nested loops, simple scalar/reference/slice parameters,
scalar results, and a call site inside a loop. It preserves explicit `inline`
and excludes ordinary remaining Goose calls, dispatch/function values, nested
captures, nonlocal exits, unsized parameters and pooled references.

Byte filling requires a single plain byte store over a stable LOCAL slice's
length, an immutable I64 binder, and a same-storage byte literal or LOCAL value.
The widened physical range must fit in current linear memory. Otherwise the
original loop preserves sequential writes and traps, including malformed and
empty views. Modules with region cursors retain the original path because their
addresses can be redirected after relocation. No stdlib or workload names are
matched. Astra reviewed both eligibility gates at xhigh effort.

The final code-size heuristic also preserves entry-point fills outside an
enclosing loop and fills in synthesized global startup. A broader version
changed the custom hash's untimed preparation code and measured 0.971× on V8
(2.94% longer median execution, with all five paired ratios below one). The
scoped rule restores CRC32 and custom hash byte-for-byte, preserving their
existing engine behavior. Ordinary functions and fills inside an entry-point
loop remain eligible. This is a cost heuristic, not an execution-count proof.

| Experiment | V8 sieve speedup | Wasmtime sieve speedup | Decision |
| --- | ---: | ---: | --- |
| Retention alone, current emitter | 8.026× | 0.797× | Reject alone |
| Byte fills alone | 1.195× | 1.319× | Keep as part of the combined candidate |
| Scoped retention plus byte fills | 9.398× | 1.084× | Balanced default |

Each row is a separate five-pair comparison against the frozen baseline.
Do not combine ratios or interpret these separate cohorts as a direct paired
comparison between candidates. The fill-only control shows further Wasmtime
headroom, while leaving the large V8 gap. The combined default improves both
engines over the pushed baseline. Directly pairing these two candidates and
profiling the current marking loops is a remaining hill.

The older [rejected broad policy](../runtime/README.md) predates scalar-write
cleanup. Static native-code inspection showed different zero materialization
inside its marking loop, but it was not a sampled profile or an isolated proof
of the regression's cause. The current retention-only measurement above
reproduces the regression on the current emitter.

## Evidence

- [Baseline qualification](baseline.json): 35 checks across all seven adapted workloads.
- [Final candidate qualification](candidate.json): 35 checks across all seven workloads.
- [Paired timings/builds](paired.json).
- [Retention qualification](retention.json) and [paired retention measurements](retention-paired.json).
- [Fill-only qualification](fill-only.json) and [paired fill-only measurements](fill-only-paired.json).
- [Unscoped qualification](unscoped-ports.json), [sieve pairs](unscoped-paired.json),
  and [hash pairs](unscoped-hashes-paired.json) preserve the rejected broader fill scope.
- [Artifact comparison](artifact-comparison.json): all six controls are byte-identical;
  only sieve changes.
- [Exact compiler source patches](source-snapshots.tar.gz): apply to `3065a72`.

## Correctness qualification

All gates pass against the final scoped compiler:

| Gate | Result |
| --- | ---: |
| Default O0/O2 native/C-Wasm/direct matrix | 9,090 runtime observations passed |
| Explicit compile refusals | 3 passed |
| Aggregate returns and scalar math extensions | 100 checks passed |
| Byte fills, physical boundaries and entry-point scope | 4 tests passed; 28 engine runtime cases |
| Sparse static data | 4 tests passed |
| Stable regions and scoped cleanup | 111 tests passed |
| Dynamic storage/lifetime boundaries | 4 tests passed |
| Native compiler sessions and fixture equivalence | 12 tests passed |
| Incremental cache/driver integration | 12 checks passed |
| Capability inventory consistency | 113 entries, 0 errors |

New differential cases cover callable nested kernels, reference/slice mutation,
call counts, bounds failures, signed/unsigned bytes, runtime values, sentinels,
effects, reference RHS values, changing values and rebound source views.
Structural checks prove retention, the explicit-inline override, both sides of
the entry-point scope gate and the region-cursor exclusion. Host-injected views
verify empty pointers at/beyond memory, partial writes before an end-crossing
trap, and overflowing ranges on both engines at O0/O2.

[Qualification summary and source hashes](qualification.json),
[full differential observations](differential.json.gz),
[extension observations](backend-extensions.json), and
[qualification logs](qualification-logs.tar.gz) retain the evidence.
Expected compile refusals remain separate from executed programs.
