# CRC32 and custom hash — 2026-11-01

Baseline: repository commit `dda008c`. Candidate: retain repeated loop kernels,
fold short unsigned bit recurrences into independent XOR terms, and emit small
sequence loops in groups with constant lane indices. Only the direct backend
changes. Workload algorithms, sources, production inputs, warmups and engine
flags stay fixed. The workload named `Hash::SHA256` is LangArena's custom
eight-lane digest, not cryptographic SHA-256.

AMD Ryzen 7 3800X, 16 logical CPUs, Linux 7.3.0-4-cachyos, shared desktop host.
Node 24.22.1 / V8 13.6.233.17-node.58, Wasmtime 50.0.1, Emscripten 6.0.13.
Goose `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, built with Clang 23.1.4,
CMake 4.4.4 and Ninja 1.13.2. Native C uses GCC 16.2.1.
[Compiler/source identities](compiler-identities.json).

## Current backend comparison

One fresh cohort measures all three backends with the current compiler, five
samples per cell and identical adapted sources. Six ports replace growable
storage with bounded arrays. These seven ports do not represent the full
50-task suite. Direct Wasm uses memory32; C-to-Wasm uses memory64. Backends are
not interleaved pairs. All 315 observations passed, identities stayed fixed,
and every rebuilt direct module matches its qualified artifact.

Complete uncached build medians in milliseconds, including Python startup.
Values after ± and chart whiskers show MAD; OS caches remain warm.

| Workload | Direct Wasm ms ±MAD | C → Wasm ms ±MAD | C → native ms ±MAD |
| --- | ---: | ---: | ---: |
| Fannkuch | 74.0 ±3.4 | 669.0 ±7.2 | 309.1 ±7.3 |
| Mandelbrot | 75.5 ±2.3 | 646.7 ±14.7 | 284.3 ±2.9 |
| Sieve | 73.8 ±1.1 | 658.4 ±11.2 | 307.9 ±17.9 |
| CRC32 | 70.8 ±2.2 | 653.2 ±5.6 | 268.1 ±0.8 |
| Custom hash | 76.8 ±4.1 | 658.0 ±8.1 | 329.8 ±8.0 |
| Merge sort | 76.1 ±0.8 | 673.3 ±6.2 | 317.1 ±1.2 |
| Quicksort | 74.8 ±1.2 | 647.0 ±31.5 | 288.1 ±4.9 |

Runtime medians in seconds per configured measured iteration count, excluding
preparation, warmups and startup. Native is repeated in both chart panels.
Raw samples retain dispersion and engine compilation/instantiation costs.

| Workload | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime | Native |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fannkuch | 1.388 | 2.333 | 1.452 | 1.592 | 1.371 |
| Mandelbrot | 1.019 | 1.005 | 1.074 | 1.108 | 0.968 |
| Sieve | 1.453 | 6.077 | 1.538 | 5.615 | 0.903 |
| CRC32 | 0.683 | 0.476 | 0.680 | 0.428 | 1.412 |
| Custom hash | 1.144 | 1.166 | 1.102 | 1.044 | 0.629 |
| Merge sort | 2.149 | 1.407 | 2.155 | 2.855 | 1.461 |
| Quicksort | 1.482 | 1.491 | 1.660 | 1.721 | 1.252 |

[cohort.json](cohort.json) retains every observation. [readme.json](readme.json)
selects chart rows through [latest.json](../../latest.json); SVG metadata retains
source hashes. Do not combine absolute times from separately collected cohorts.

```sh
source build/performance-env.sh
python bench/langarena.py measure --tracks adapted --backends native c-wasm direct \
  --compile-samples 5 --runtime-samples 5 --skip-edits \
  --output-dir build/performance/hash-cohort \
  --machine-label 'AMD Ryzen 7 3800X, shared desktop host'
```

## Final paired measurements

Five interleaved baseline/candidate pairs per engine use identical production
inputs at Goose O2. Complete cold builds reproduce each qualified module.
All small-input and production checksums pass on both engines. Task/engine
order and variant order within each pair are shuffled with the retained seed.
The two hash tasks and two sorts are separate paired cohorts.

| Workload | Engine | Before seconds ±MAD | After seconds ±MAD | Speedup | Paired speedup range |
| --- | --- | ---: | ---: | ---: | ---: |
| Custom hash | v8 | 6.2198 ±0.0406 | 1.1535 ±0.0050 | 5.392× | 5.160–5.666× |
| Custom hash | wasmtime | 1.5233 ±0.0067 | 1.1157 ±0.0005 | 1.365× | 1.319–1.457× |
| CRC32 | v8 | 4.1732 ±0.0300 | 0.7087 ±0.0098 | 5.888× | 5.692–6.125× |
| CRC32 | wasmtime | 0.9726 ±0.0044 | 0.7028 ±0.0047 | 1.384× | 1.259–1.420× |
| Quicksort | v8 | 1.5894 ±0.0544 | 1.6340 ±0.1136 | 0.973× | 0.861–1.054× |
| Quicksort | wasmtime | 1.8044 ±0.0858 | 1.7588 ±0.0503 | 1.026× | 0.875–1.056× |
| Merge sort | v8 | 2.2966 ±0.0417 | 2.1834 ±0.0134 | 1.052× | 1.033–1.121× |
| Merge sort | wasmtime | 2.3095 ±0.1164 | 2.3146 ±0.1225 | 0.998× | 0.991–1.033× |

Quicksort's 2.8% V8 time increase is within its dispersion and below the 3%
investigation threshold; it is retained as a control, not an improvement claim.
The other three workload modules are byte-identical. Changed module/code sizes:

| Workload | Module bytes before → after | Code bytes before → after |
| --- | ---: | ---: |
| CRC32 | 4466 → 3691 | 3238 → 2448 |
| Custom hash | 6313 → 7710 | 5053 → 6435 |
| Quicksort | 6337 → 4984 | 5070 → 3702 |
| Merge sort | 7516 → 5798 | 6211 → 4478 |

Custom hash spends 22% more module bytes on grouping and tails. CRC32 shrinks
17%, and both sort modules shrink. Total bytes across the seven modules fall
from 38,079 to 35,630 (6.4%). Paired complete builds include Python
startup; emitter times measure only the backend, so they are not additive.

| Workload | Build ms before ±MAD | Build ms after ±MAD | Emitter ms before ±MAD | Emitter ms after ±MAD |
| --- | ---: | ---: | ---: | ---: |
| Custom hash | 82.50 ±3.74 | 81.93 ±1.28 | 1.282 ±0.001 | 1.332 ±0.017 |
| CRC32 | 82.27 ±2.85 | 77.52 ±2.56 | 1.435 ±0.090 | 1.225 ±0.037 |
| Quicksort | 98.43 ±7.37 | 77.66 ±3.58 | 5.022 ±0.614 | 2.771 ±0.122 |
| Merge sort | 82.67 ±3.57 | 82.21 ±6.33 | 4.127 ±0.107 | 4.096 ±0.228 |

Build results are mixed; this batch establishes runtime gains, not a general
compilation-speed improvement. [paired.json](paired.json) and
[sort-paired.json](sort-paired.json) retain all samples, including startup.

```sh
python bench/compare_runtime.py build/performance/hash-baseline/report.json \
  build/performance/hash-strip/report.json --filter Hash --samples 5 \
  --output-dir build/performance/hash-final-paired
python bench/compare_runtime.py build/performance/hash-baseline/report.json \
  build/performance/hash-strip/report.json --filter Sort --samples 5 \
  --output-dir build/performance/hash-sort-paired
```

## Experiments and remaining hills

The unchanged compiler's diagnostic runs take CRC32 from 3.972 to 0.959 seconds
and custom hash from 6.186 to 1.616 when V8 is forced directly into its optimizing
tier. This is diagnostic evidence for preserving repeated kernel entry points;
headline runs use default V8 flags. These single runs are not benchmark medians.
[tiering.json](tiering.json) pins the modules, commands and official checksums.

1. **Call policy.** Retain scalar-return kernels with at least one substantial
   loop, or smaller nested loops, at repeated call sites. Ordinary calls outside
   loops are permitted, while ordinary Goose calls within loops, closures,
   dynamic dispatch and complex lifetimes retain the prior rules. Explicit inline and native/C-Wasm
   policy are unchanged. Alone this gives CRC32 4.130×/0.984× and custom hash
   3.746×/0.963× (V8/Wasmtime). The custom-hash Wasmtime regression makes this
   insufficient alone. [retention-paired.json](retention-paired.json).
2. **Missed bit fold.** The first matcher assumed a sole statement, but the CRC
   loop stores its conditional as a block tail. It produced a byte-identical
   CRC module and 1.004×/0.994×, so no gain is attributed to it.
   [missed-fold-paired.json](missed-fold-paired.json).
3. **Corrected bit fold.** Match either sole-statement or sole-tail shape.
   An exact local unsigned 32/64-bit recurrence with a literal polynomial and
   1–8 rounds is linear in its low bits. Compute basis columns at compile time
   and combine independent terms in a balanced XOR tree. No table or new memory
   contract is introduced. CRC improves 1.403×/1.388× over the callable version,
   shrinking 3,868 to 3,691 bytes and eliminating its eight selects.
   [fold-paired.json](fold-paired.json).
4. **Constant lanes.** Reuse frontend strip analysis for 2–8 lanes, with scalar
   immutable binders, invariant sequence length and a 128-node straight-line
   budget. Emit full groups followed by guarded tails, replacing only the
   frontend's exact proven remainder nodes. Complete each lane's load, stores
   and possible traps before loading the next lane. Calls, exits, captures,
   addressed locals, references and region modules use the ordinary path.
   Custom hash improves 1.431×/1.422× over the callable version.
   [strip-paired.json](strip-paired.json).

Those experimental ratios come from separate cohorts and must not be
multiplied into a claimed final gain. The final pairs above directly compare
the delivered combination against the pushed baseline.

Inspection of the pinned generated C-Wasm shows LLVM turns CRC's recurrence
into a 256-entry table; direct Wasm still computes arithmetic terms. A compiler
table would be observable and writable through exported linear memory, so this
batch chooses the arithmetic fold. Faster table-free CRC remains a hill.
Custom hash still loads/stores its lane array; scalar replacement is a separate
follow-up. [machine-inspection.tar.gz](machine-inspection.tar.gz) retains the
Wasmtime native disassemblies and before/after direct CRC Wasm text. Direct and
C-Wasm use different address widths; their bounds-check costs are not identical.

## Correctness and source evidence

The full O0/O2 differential gate passes 9,450 runtime observations plus three
expected compile refusals. It includes 120 new bit-fold observations and 240
new blocked-loop observations, comparing native C, C-Wasm and direct Wasm on
both engines against independent answers. Cases cover polynomial/width/binder
fallbacks, zero lengths, full groups, tails, calls, captures and view rebinding.
The additional host suite passes 52 engine/level/debug cases for physical
bounds and ordered arithmetic traps, plus four structural remainder checks.
Existing fill, extension, static-data, region, boundary, compiler-session,
incremental and capability checks pass too. Session checks cover the retained
hash entry points and fresh-compiler byte equivalence of all registered fixtures.

[qualification.json](qualification.json) records counts, commands and runner/
fixture hashes. [differential.json.gz](differential.json.gz),
[backend-extensions.json](backend-extensions.json) and
[qualification-logs.tar.gz](qualification-logs.tar.gz) retain the results.

[source-snapshots.tar.gz](source-snapshots.tar.gz) contains each experimental
compiler-only repository diff against `dda008c`, plus its frozen bootstrap source
and toolchain identities. Every snapshot was reconstructed from that commit
and checked against its recorded header/patch hashes. The baseline diff is empty.
These repository diffs modify the nested upstream patch; apply them to the
repository and run bootstrap, rather than applying them to managed `build/source`.
Reports retain absolute local paths as provenance; compiler binaries and build
trees are not included. [SHA256.json](SHA256.json) covers retained evidence.
