# Basis selects and cached lanes — 2026-11-01

Baseline: repository commit `efb1788`. Candidate: emit CRC basis terms with
selects, cache small fixed-array lanes with immediate memory stores, and use
known frame offsets for cached targets. Benchmark algorithms, sources, inputs,
warmups and engine flags stay fixed. `Hash::SHA256` is LangArena's custom
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
| Fannkuch | 73.3 ±0.6 | 659.4 ±14.3 | 327.4 ±13.5 |
| Mandelbrot | 78.6 ±5.5 | 641.6 ±12.4 | 308.3 ±2.0 |
| Sieve | 78.1 ±1.4 | 652.1 ±13.6 | 299.2 ±5.5 |
| CRC32 | 74.3 ±1.8 | 650.4 ±10.5 | 292.1 ±4.0 |
| Custom hash | 75.2 ±1.4 | 659.1 ±10.3 | 306.9 ±6.2 |
| Merge sort | 77.2 ±0.4 | 658.0 ±11.2 | 338.9 ±9.3 |
| Quicksort | 82.5 ±3.2 | 658.7 ±22.7 | 302.5 ±6.3 |

Runtime medians in seconds per configured measured iteration count, excluding
preparation, warmups and startup. Native is repeated in both chart panels.
Raw samples retain dispersion and engine compilation/instantiation costs.

| Workload | Direct / V8 | C-Wasm / V8 | Direct / Wasmtime | C-Wasm / Wasmtime | Native |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fannkuch | 1.409 | 2.381 | 1.494 | 1.625 | 1.419 |
| Mandelbrot | 1.030 | 1.022 | 1.103 | 1.134 | 0.981 |
| Sieve | 1.482 | 6.253 | 1.596 | 5.621 | 0.947 |
| CRC32 | 0.550 | 0.494 | 0.475 | 0.431 | 1.425 |
| Custom hash | 1.054 | 1.170 | 1.027 | 1.064 | 0.645 |
| Merge sort | 2.165 | 1.458 | 2.197 | 2.850 | 1.493 |
| Quicksort | 1.498 | 1.519 | 1.698 | 1.754 | 1.263 |

[cohort.json](cohort.json) retains every observation. [readme.json](readme.json)
selects chart rows through [latest.json](../../latest.json); SVG metadata retains
source hashes. Do not combine absolute times from separately collected cohorts.

```sh
source build/performance-env.sh
python bench/langarena.py measure --tracks adapted --backends native c-wasm direct \
  --compile-samples 5 --runtime-samples 5 --skip-edits \
  --output-dir build/performance/next-cohort \
  --machine-label 'AMD Ryzen 7 3800X, shared desktop host'
```

## Final paired measurements

Five interleaved baseline/candidate pairs per engine use identical production
inputs at Goose O2. Complete cold builds reproduce each qualified module.
All small-input and production checksums pass on both engines. Task/engine
order and variant order within each pair are shuffled with the retained seed.
Both hash tasks are measured in one interleaved cohort.

| Workload | Engine | Before seconds ±MAD | After seconds ±MAD | Speedup | Paired speedup range |
| --- | --- | ---: | ---: | ---: | ---: |
| Custom hash | v8 | 1.1310 ±0.0023 | 1.0405 ±0.0065 | 1.087× | 1.084–1.104× |
| Custom hash | wasmtime | 1.1026 ±0.0109 | 0.9979 ±0.0005 | 1.105× | 1.091–1.118× |
| CRC32 | v8 | 0.6781 ±0.0057 | 0.5406 ±0.0008 | 1.254× | 1.244–1.268× |
| CRC32 | wasmtime | 0.6892 ±0.0031 | 0.4605 ±0.0006 | 1.497× | 1.490–1.512× |

Only the two hash modules change; the other five remain byte-identical.

| Workload | Module bytes before → after | Code bytes before → after |
| --- | ---: | ---: |
| CRC32 | 3691 → 3664 | 2448 → 2421 |
| Custom hash | 7710 → 6635 | 6435 → 5360 |

Custom hash shrinks 14%; CRC32 is slightly smaller. Total bytes across all
seven modules fall from 35,630 to 34,528 (3.1%). Complete builds include Python
startup; emitter measurements are a subset of that wall time.

| Workload | Build ms before ±MAD | Build ms after ±MAD | Emitter ms before ±MAD | Emitter ms after ±MAD |
| --- | ---: | ---: | ---: | ---: |
| Custom hash | 80.34 ±3.51 | 77.59 ±5.77 | 2.211 ±0.048 | 1.498 ±0.017 |
| CRC32 | 75.09 ±5.54 | 72.43 ±2.06 | 1.129 ±0.016 | 2.337 ±0.256 |


Build and emitter samples are retained alongside startup timings in
[paired.json](paired.json). No general compilation-speed claim is made.

```sh
python bench/compare_runtime.py build/performance/next-baseline/report.json \
  build/performance/next-address/report.json --filter Hash --samples 5 \
  --output-dir build/performance/next-final-paired
```

## Experiments and remaining hills

1. **Basis selects.** Each nonzero bit term selects its constant column or
   zero using the corresponding bit of the saved state. The existing balanced
   XOR tree and exact unsigned 32/64-bit recurrence matcher remain. Wrapping a
   64-bit state to i32 for the condition preserves all tested low bits. This
   removes serial mask arithmetic without introducing memory tables. CRC32
   improves 1.254× on V8 and 1.508× on Wasmtime, shrinking 3,691 to 3,664 bytes.
   [select-paired.json](select-paired.json).
2. **Lane cache.** Load at most eight checked fixed-frame integer elements
   into Wasm locals before an eligible blocked loop. Arrays must have 32/64-bit
   elements and the same fixed arity as its 2–8 lanes. Each cached access uses
   an exact frontend-proven remainder or an immutable i64 local initialized
   from it. Any other index invalidates that array; any unrecognized memory
   write disables all caching. Calls and region modules retain their old path.
   Addressed or captured arrays are excluded. Reads preserve their conversions;
   converted writes update the cache then immediately perform the original
   memory store. This preserves source aliases and partial stores before later
   traps. Custom hash gives 1.006×/1.101× (V8/Wasmtime) and shrinks 7,710 to
   7,270 bytes. V8 is flat here; no V8 win is claimed for caching alone.
   [cache-paired.json](cache-paired.json).
3. **Known addresses.** A cached target's array, frame offset and lane are
   already known. Pin that location directly before evaluating the RHS,
   replacing pure view/index work that cannot trap. Retain the store in its
   original position. Custom hash adds 1.068×/1.012× over caching and shrinks
   7,270 to 6,635 bytes. Wasmtime is effectively flat for this step.
   [address-paired.json](address-paired.json).

All three changes are kept. Experimental ratios come from separate cohorts;
the final pairs above compare the delivered combination directly with the
pushed baseline. They must not be reconstructed by multiplying those ratios.

Hash `run` has 18 → 10 explicit i32 loads, 25 → 25 i32 stores and 208 → 136
Wasm locals (103 → 95 i32, 105 → 41 i64). CRC's update changes from eight
right shifts and no selects to one right shift and eight selects.
These are S-expression opcode/declaration counts, not native instruction
counts. [instruction-inspection.json](instruction-inspection.json) pins the
before/after artifacts and counts; [the Wasm text](instruction-inspection.tar.gz)
is retained. Flat V8 cache results do not establish whether its optimizer was
already forwarding stores.

Packed two-bit CRC constants, shift-mask omission and scratch-local pooling
remain unmeasured follow-ups. Pooling needs a broader lifetime proof; remaining
literal masks may already fold in the engines. No mutable lookup table,
scratch pool or engine flag is introduced in this batch.

## Correctness and iteration time

The full O0/O2 matrix passes 9,450 runtime observations and three expected
compile refusals: 1,890 native, 3,780 C-Wasm and 3,780 direct executions, with
both Wasm engines. Its existing backend jobs run concurrently in separate
directories. The merge rejects duplicate/missing execution keys using each
case's level restrictions, requires all shards to pass, and replays every
one of the 7,560 native-stdout comparisons. Backend diagnostic checks stay in
the original runner. Eight positive/fault checks and replay of the retained
previous full matrix validate the merge; that replay is not new-compiler
qualification.

The focused host suite passes 100 runtime cases and six structural checks.
Cases include live frame-store inspection after physical/division/overflow
traps, forged source views into the cached array, short/empty tails, aliased
write fallbacks, calls, references and captures. The existing 24 strip cases
now also check signed i32 and unsigned u64 repeated reads/writes, compound
updates and increments, including signed i32 reads widened into i64. Their
31 numeric outputs are calculated independently. Bit-fold checks retain
arbitrary polynomials, widths and fallback shapes.

All extension, fill, static-data, region, dynamic-boundary, compiler-session,
incremental and inventory gates pass. [qualification.json](qualification.json)
records commands, counts and fixture/runner hashes;
[differential.json.gz](differential.json.gz),
[differential-shards.tar.gz](differential-shards.tar.gz),
[backend-extensions.json](backend-extensions.json) and
[qualification-logs.tar.gz](qualification-logs.tar.gz) retain the results.

```sh
source build/performance-env.sh
python bench/results/2026-11-01/lanes/run-matrix.py \
  --goose build/runtime-next-address/bin/goose \
  --output-dir build/performance/next-full-differential
```

The wrapper records listed inputs, rather than an exhaustive dependency
closure. [qualification-inputs.json](qualification-inputs.json) separately
records the six JSON oracle files (unchanged from `efb1788`), installed stdlib,
and actual tool identities. Those hashes are verified again before delivery.
Qualification runs under contention; its timings are separate from performance
measurements, which start after every correctness process finishes.

The complete matrix and merge took 951.8 seconds (15.9 minutes) in this run. No speedup ratio is claimed against a different compiler or workload snapshot.

## Compiler-phase follow-up

CRC's paired cold emitter median rises from 1.129 to 2.337 ms, while complete
build medians fall from 75.09 to 72.43 ms within their dispersion. A diagnostic
with two warmups and twelve shuffled pairs in persistent compiler workers
confirms a smaller recurring emitter cost: 0.510 ±0.026
to 0.744 ±0.013 ms. Lexical caching is enabled,
artifact caching and typed-frontend reuse are disabled, and every module matches
its qualified artifact. This is a warm-worker phase diagnostic, not the README's
cold-build measurement. The extra roughly 0.23 ms is retained as a tradeoff and
another emitter hill; no overall compilation-speed improvement is claimed.
[emitter-probe.json](emitter-probe.json) and [its source](probe-emitter.py).

## Source evidence

[source-snapshots.tar.gz](source-snapshots.tar.gz) contains each compiler-only
repository diff against `efb1788`, plus its frozen bootstrap source and toolchain
identities. Each snapshot was reconstructed from that commit and checked
against its header/patch hashes. The baseline diff is empty. Apply these diffs
to the repository and bootstrap, rather than editing managed `build/source`.
Reports retain absolute local paths as provenance; compiler binaries and build
trees are not included. [SHA256.json](SHA256.json) covers retained evidence.
