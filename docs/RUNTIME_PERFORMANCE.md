# Runtime performance work

## Guarded merge loops

Eligible merge loops over 32- or 64-bit integer slices with stable local views and cursors check complete logical and physical source and destination spans before entering a branchless loop. The loop retains the original comparison, loads both candidates, selects the value to store and advances the corresponding cursor. The fast path preserves overlap behavior and access order. Failed guards and debug builds retain the scalar loop, including partial effects on traps.

Nine paired warmed Wasmtime rounds measured Merge from 2,114.235 to 1,544.564 ms, a 1.369× paired speedup (MAD 0.059). V8 measured 1,911.894 to 1,463.426 ms, a 1.308× paired speedup (MAD 0.009). The separately built selected native reference took 1,104.079 ms in the Wasmtime paired cohort; it remains faster on this workload. The insertion-sort adapter is a byte-identical control. V8 Life was also byte-identical and measured 0.965× (MAD 0.044), illustrating control variation. The full Sorting module grows from 48,269 to 48,582 bytes; its merge body grows from 995 to 1,308 bytes. The Merge port grows from 5,214 to 5,527 bytes. These timings measure warmed kernels, not full Sorting process launches.

A guard-only variant was rejected after V8 elapsed time rose 19%. A minimum span of 16 gained about 1.5% on Wasmtime over the selected variant but raised V8 elapsed time 3.9%; neither mechanism was isolated. A resident-host InstancePre experiment saved about 2 µs of preparation, but 201 paired Functions round trips showed only 1.005× (MAD 0.029), so it was rejected. The retained branchless strategy resembles the selected native Clang output. [Measurements and retained experiments](../bench/results/2026-11-03/merge-bounds/README.md) record the comparisons.

## Resource-free calls

Proven resource-free recursive and fixed-reference calls omit frames, including numeric inline occurrences. In full-example entry probes, Sudoku's separate medians fell from 12.137 to 6.009 ms on V8 and 3.757 to 2.992 ms on Wasmtime. Median paired speedups were 1.642× (ratio MAD 0.326) and 1.259× (MAD 0.032); V8 varied more. Its module shrank from 11,953 to 10,966 bytes. The other nine modules were byte-identical, so timing changes there are noise. Nine fresh warmed reference rounds measured the Sudoku adapter at 1.066× baseline/current (MAD 0.002). The first SCC-only experiment (`f0d`) changed none of the ten modules; numeric inline support was needed. [Evidence](../bench/results/2026-11-02/resource-free-calls/README.md) records both.

## Native execution hills

Leaf-frame removal, exact unsigned `popcnt`, power-of-two signed remainder, limited literal-divisor clones and direct unrolled-loop guards improve selected examples. Fifteen paired Wasmtime entry probes measured Life 24.256 → 12.953 ms, Sudoku 6.541 → 3.836 ms and Sorting 86.565 → 66.117 ms. Entry includes initialization and callbacks. Eight- and sixteen-way unrolling were rejected; four-way remains. The [dated evidence](../bench/results/2026-11-02/native-hills/README.md) includes controls, qualification and fresh process results.

## Raw array images

Closed modules with only raw array images omit mode dispatch, except where explicit public exports or nonintrinsic user imports permit host memory edits. Across ten examples, module bytes fell from 412,112 to 275,693. Nine paired entry probes measured Sorting at 117.886 → 95.214 ms on V8 (1.240× paired, MAD 0.036) and 108.351 → 90.102 ms on Wasmtime (1.194×, MAD 0.080). Entry includes initialization, callbacks and possible lazy JIT. The separate fresh process cohort and qualification are in the [dated evidence](../bench/results/2026-11-02/raw-array-images/README.md); the [audit](WASM_AUDIT.md) records remaining hills.

## Sorting loop unrolling

Profiles of baseline `7957d3c` (compiler SHA-256 `3316710bb9d2b3100e94c2023000f0cb1b7517010ef04076314b4703fdcfcbba`) put both native and Wasm Sorting in insertion sort. Its hot loop has no calls, explicit language bounds checks, mode checks or global stores; Wasm's hardware memory guard remains. The direct emitter now unrolls eligible local-index loops four ways: it emits one balanced iteration and copies its bytes three times, sharing locals and branch depths. Eligibility requires a local integer increment and pure local slice/scalar operands, without source calls, declarations, control flow or owners. Conditions, traps, stores and cleanup retain their order; no load CSE was kept.

Nine paired entry probes with the native C++ Wasmtime 50.0.1 host measured Sorting at 141.475 → 90.029 ms (paired median speedup 1.398×, MAD 0.221); V8 measured 116.330 → 113.109 ms (0.961×, MAD 0.090), with no established gain. Squares, Sudoku, Maze and Life modules were byte-identical and their timing changes were noise. Six nearby source variants measured 1.146–1.473× on Wasmtime in five pairs; a weak V8 case repeated over 15 pairs measured 0.991× on V8 and 1.333× on Wasmtime. These are entry probes, not full-process results.

Direct `&&` branches and nested guards gave roughly 1.5× on Wasmtime, and load CSE roughly 1.15×, but each triggered roughly 4× slower default V8 execution. Two-way unrolling also slowed V8; four-way unrolling avoided that cliff, while adding caching gave no further Wasmtime gain. V8 traces and separate engine-flag controls support a tiering threshold explanation, not a fixed Wasm cost: the inner backedge charged 307 budget units at baseline versus 255 with CSE, approximately corresponding to bytes executed, while the global budget remained 13,000,000; code optimized later. The final Sorting module matches the retained four-way experiment byte for byte (`cd182e10e03dd0c0e4be69826119d5d6e96b1cad048b9ec8d4c70586778c0b26`). [Dated evidence](../bench/results/2026-11-02/sorting-execution/README.md) records the experiments, qualification and refreshed full-process results.

## Prefix dispatch and startup

The final array-image dispatch uses a branch table, keeps fixed-prefix paths inline, and outlines ULEB handling until encountered ULEB types select an inline preference. Header dispatch, bounds and operation order remain intact. Across 12 hot-mode control cells, all 60 paired ratios exceeded 1, with median speedups of 1.26–3.61×; these samples do not establish confidence bounds. Seven paired fresh-process entry probes per cell measured sorting at 145.846 → 116.537 ms on V8 (1.254×) and 118.511 → 117.777 ms on Wasmtime (1.004×); maze improved 2.639× and Life 1.556× on V8, with Wasmtime entry times flat. Squares stayed byte-identical with flat entry time; its 0.881× process ratio illustrates launch noise. Instrumented process ratios are diagnostic, not ordinary launch-to-exit benchmarks.

Removing block watermarks was rejected: sorting on V8 slowed 3.7×. Sharing all non-raw image access through three helpers (base, length and write) added 12–18% to Wasmtime hot-prefix cost. A hybrid guard was also rejected: ULEB on V8 reached 0.838× and runtime-limited access on Wasmtime 0.909×.

A 15-pair Life build control investigated a noisy five-pair candidate build time. Complete build medians were effectively flat at 68.525 → 68.747 ms (0.988× paired, MAD 0.022); emitter medians fell from 0.523 to 0.430 ms (1.213× paired, MAD 0.035). This does not establish a general compilation speedup.

Separate startup controls measured native empty process 0.702 ms, `node -e` 19.999 ms, empty Goose on Node 26.850 ms, empty Python 9.212 ms, Python importing Wasmtime 43.862 ms and empty Goose on Python-hosted Wasmtime 78.134 ms. These are independent observations, not additive costs or hard bounds. They show why small whole-process examples have a host startup hill alongside generated-code work.

Astra reviewed the plan and implementation. Qualification passed 9,453 differential observations with 7,560 native stdout comparisons, plus 44 focused commands including the 60-build/100-execution example matrix. The ordinary ten-example cohort passed 1,600 observations. Sorting launch-to-exit medians were 157 ms direct on V8, 252 ms on Python-hosted Wasmtime and 50 ms native. The separate LangArena cohort passed 315 observations; all seven direct modules were byte-identical to the preceding cohort, so it establishes no kernel gain from this change. The [dated record](../bench/results/2026-11-02/native-gap/README.md) retains measurements and tradeoffs; see the [native-host phase evidence](../bench/examples.md#native-gap) for newer measurements.

## Prefix resolution

The sorting profile attributed 74.9% of samples to `resolve_prefix`: 401,711,695 calls checked 2,812,502,155 owner entries despite having no active mappings or remaps. The workload remains at 20,000 insertion values; only its misleading source header and manifest description were corrected.

The emitter tracks actual positive-prefix registrations and makes the resolver an identity when there are none. It emits the start body before choosing that helper so global constructors count. Separately, the complete checker-owned `Ast::structinsts` registry proves whether frame-record types exist before function emission; when none exist, resolver calls are omitted entirely. A guard rejects a registration that contradicts this early proof. Positive-prefix frame modules retain the original resolver, and header publication, ownership, bounds and unwind behavior remain intact. No runtime counters or globals were added.

Sorting Wasm shrank from 144,519 to 138,792 bytes, with no resolver callers. The identity-only stage measured 15.84× on V8 and 6.18× on Wasmtime in five paired sorting **entry** probes; those figures are separate from ordinary launch-to-exit timing. The final variant, measured in seven pairs per cell across five examples, reduced sorting entry time 26.292× on V8 and 34.608× on Wasmtime; Sudoku improved 18.439× and 29.814×. The experiment used 50 builds, 20 warmups and 140 measured probes. Squares remained byte-identical with unchanged entry time; instrumented process time varied by about 10%. Maze showed no reliable V8 change and improved 1.217× on Wasmtime; Life improved 2.043× on Wasmtime. Startup and engine tiering remain hills.

Qualification passed 9,453 differential observations, including 7,560 native stdout comparisons, and 43 focused commands, including region and prefix cases, warm CLI fixture parity, and the 60-build/100-execution example matrix. The [dated evidence](../bench/results/2026-11-02/prefix-resolution/README.md) retains the measurements and details.

## Basis selects and cached lanes

Starting from `efb1788`, replace each CRC basis mask with a select of its
constant column or zero, preserving the balanced XOR tree. Cache small fixed
array lanes in Wasm locals across eligible blocked loops, retaining every
memory store immediately. Known cached targets then use their constant frame
offsets instead of rebuilding a slice view and index. Astra reviewed the plan
and implementation at xhigh effort. Benchmark sources, inputs, warmups and
engine flags stay unchanged.

Five interleaved baseline/final pairs per engine:

| Workload | V8 seconds before → after | Speedup | Wasmtime seconds before → after | Speedup |
| --- | ---: | ---: | ---: | ---: |
| CRC32 | 0.6781 → 0.5406 | 1.254× | 0.6892 → 0.4605 | 1.497× |
| Custom hash | 1.1310 → 1.0405 | 1.087× | 1.1026 → 0.9979 | 1.105× |

CRC32 shrinks from 3,691 to 3,664 bytes; custom hash from 7,710 to 6,635
bytes (14%). The other five modules remain byte-identical. In the hash's
emitted `run` function, 32-bit loads fall from 18 to 10, stores remain at 25,
and Wasm locals fall from 208 to 136. These are Wasm instruction/declaration
counts, not native machine-code counts.

The cache holds at most eight 32/64-bit integer elements in checked fixed
frame storage. Its exact lane indices are pure and in bounds. Any unrecognized
memory write disables caching. Addressed or captured arrays, calls and region
modules keep the existing path. Immediate stores preserve input aliases and
partial writes before later traps. Wider signed reads and compound/increment updates
keep their existing conversions and checks.

The cache alone improves Wasmtime 10% with flat V8, and shrinks the module
5.7%. The address shortcut adds 6.8% on V8 with effectively flat Wasmtime.
Those experiments are separate cohorts, not factors to multiply into the final
ratios above. Scratch-local pooling and packed two-bit CRC terms remain
unmeasured follow-ups; neither is part of the delivered compiler.

CRC's emitter cost rises in a warm-worker diagnostic, 0.510 → 0.744 ms;
paired complete cold builds show no meaningful regression. That roughly
0.23 ms cost remains an emitter hill, alongside the runtime gains.

The [dated evidence](../bench/results/2026-11-01/lanes/README.md) retains all
pairs, compilation costs, source snapshots, correctness results and the fresh
three-backend README cohort. The full matrix runs its existing backend jobs
concurrently, then checks the exact expected row set and replays all 7,560
native-output comparisons. This preserves coverage while shortening the serial
qualification path; its timings are separate from benchmark measurements.

## Previous hill: CRC32 and custom hash

Starting from `dda008c`, keep repeated loop kernels callable, fold short
unsigned bit recurrences into independent XOR terms, and emit small sequence
loops in groups with constant lane indices. These are direct-backend changes;
benchmark sources, algorithms, inputs, warmups and engine flags stay fixed.
Astra reviewed the implementation at xhigh effort.

Five interleaved baseline/candidate pairs per engine:

| Workload | V8 seconds before → after | Speedup | Wasmtime seconds before → after | Speedup |
| --- | ---: | ---: | ---: | ---: |
| CRC32 | 4.1732 → 0.7087 | 5.888× | 0.9726 → 0.7028 | 1.384× |
| Custom hash | 6.2198 → 1.1535 | 5.392× | 1.5233 → 1.1157 | 1.365× |

The call policy also changes both sort modules; their paired measurements are
retained alongside the hashes. The other three modules remain byte-identical.
CRC32 shrinks from 4,466 to 3,691 bytes. Custom hash grows from 6,313 to 7,710
bytes, a 22% size cost for the blocked loop.

The bit fold accepts only an exact recurrence on a local unsigned 32/64-bit
state, a literal polynomial and 1–8 rounds. It replaces serial rounds with a
balanced XOR tree and adds no lookup table to exported writable memory.
The sequence path reuses frontend lane analysis for 2–8 lanes, with a bounded
straight-line body, stable length and scalar binders. Each lane retains its
original load, updates and possible traps before the next lane starts. Calls,
exits, captures, references and region modules keep the ordinary path.

The call policy alone improved V8 but made custom hash about 4% slower on
Wasmtime; it was not accepted alone. A first bit-fold matcher missed the AST
shape and produced an identical CRC32 module, with no gain. Correcting the
matcher improved CRC32 about 40% on both engines over the callable version;
blocking improved custom hash about 43%/42%. Those are separate experimental
cohorts, not factors to multiply into the final baseline comparison above.

The [dated evidence](../bench/results/2026-11-01/hashes/README.md) records raw
pairs, compiler/source identities, rejected experiments, compilation costs,
correctness qualification and a fresh three-backend README cohort. CRC32 still
has arithmetic work to remove relative to LLVM's table-based C-Wasm output.
Custom hash still reloads/stores lane state; scalar replacement remains a hill.
Qualification also has an iteration-time hill: its 9,450 runtime subprocesses
recompile engine modules per case. Reusing a compiled module with fresh
instances and Wasmtime stores could retain isolation while reducing that work.

## Earlier hill: V8 sieve tiering

Starting from `3065a72`, combine a narrower direct-only inlining policy with
guarded byte fills. Substantial leaf kernels with nested loops stay callable at
repeated call sites, allowing V8 to enter optimized code. Explicit `inline`,
complex lifetime rules and native/C-Wasm inlining keep their existing behavior.
Simple byte-store loops use `memory.fill` only when the whole physical range
fits; otherwise they keep the original loop. Region-cursor modules also keep
the original path. A code-size heuristic preserves entry-point fills outside
enclosing loops, avoiding an observed V8 regression from changing untimed hash
preparation. All six control modules remain byte-identical. Astra reviewed both
gates at xhigh effort.

Five interleaved sieve pairs measure 13.596 → 1.447 seconds on V8 (9.398×)
and 1.694 → 1.562 seconds on Wasmtime (1.084×). The module shrinks by 873 bytes
(19.3%). Complete cold builds are effectively unchanged at 73.31 → 71.61 ms;
emitter medians fall from 3.363 to 2.550 ms. All official checksums pass.
The [dated measurements and source patches](../bench/results/2026-11-01/sieve/README.md)
retain dispersion, startup and the controls.

The current retention-only policy is rejected alone: 8.026× on V8 but 0.797×
on Wasmtime. Fill-only gives 1.195×/1.319×. These are separate baseline-paired
cohorts, not a direct paired comparison between candidates. The combined default
improves both engines over the pushed baseline; the fill-only control shows
remaining Wasmtime headroom. A direct combined/fill-only comparison and a
profile of their current marking loops remain follow-ups.

The final full O0/O2 matrix passes 9,090 runtime observations and three expected
compile refusals. Byte-fill boundary, extension, static-data, region,
dynamic-boundary, compiler-session, incremental and inventory checks also pass.

## Earlier hill: small count loops

The next batch starts from `ce282be`. Unroll literal count loops of 1–8
iterations when their body fits a 32-node budget and uses only scalar locals.
Validate the entire body before emitting; keep calls, declarations, references,
addresses, exits and nested loops on the existing path. Each copy retains normal
arithmetic checks, short-circuit evaluation and block cleanup. Astra reviewed
this gate at xhigh effort.

Five interleaved CRC32 pairs measure 1.084× on V8 and 1.085× on Wasmtime.
Every paired speedup is at least 1.060× on V8 and 1.075× on Wasmtime. The CRC32
module grows from 3,956 to 4,466 bytes (+510, 12.9%); the other six workload modules
are byte-identical. Complete cold build medians are 85.0 → 90.8 ms with
3.6/4.5 ms MAD, so this is a runtime/size tradeoff, not a compilation-speed win.
The [raw pairs and experiment records](../bench/results/2026-11-01/loops/README.md)
retain timings, startup and artifact identities.

Two smaller loop-counter experiments were rejected: omitting unused ordinals
gave CRC32 1.007×/1.049× (V8/Wasmtime); reusing compatible counters gave custom
hash 1.026×/1.039×. Neither met the 5% threshold on both engines. Their source
patches and measurements are retained; neither change is in the final compiler.

The full O0/O2 differential gate passes 8,870 runtime observations and three
expected compile refusals. Extension, static-data, region, dynamic-boundary,
compiler-session, incremental and capability-inventory checks also pass.

## Earlier arithmetic and scalar lowering

Five interleaved baseline/candidate pairs on the same Ryzen 7 3800X host:

| Workload | V8 speedup | Wasmtime speedup |
| --- | ---: | ---: |
| CRC32 | 2.31× | 4.71× |
| Custom hash | 1.49× | 1.36× |
| Sieve | 1.09× | 1.00× |

The four control workloads range from 0.978–1.036×. All seven modules shrink;
complete build timings remain mixed, with no established compilation-speed win.
The [full measurements and raw evidence](../bench/results/2026-11-01/runtime/README.md)
include medians, dispersion, startup, code size and the rejected experiments.

## First-batch plan

Astra reviewed the emitter at xhigh effort. The first two hills are small
lowering changes, measured independently before keeping their combination:

1. Use the frontend's `Binary::nonneg` proof for unsigned division, remainder
   and right shift. Replace remainder by a positive, correctly typed
   power-of-two literal with a mask, including compound assignment.
2. Replace small conditional assignments to the same Wasm local with `select`.
   Only speculate expressions made of local integer/bool reads, literals and
   explicitly allowed nontrapping operations. Keep conditions evaluated first
   and once. Keep calls, memory accesses, casts, division and checked signed
   arithmetic on the normal branch path.

The frontend already provides the arithmetic proof. No general optimization
IR, unchecked indexing, C/LLVM pass or workload-specific algorithm is needed.
The third kept change removes redundant capture/copy temporaries from
scalar assignment and increment. Values already converted to the destination
type write directly, while layout validation, pinned locations and aggregate
copies keep their existing contracts. Loop strip-mining and array scalar
replacement remain follow-ups unless measurements justify their cost.

Keep a change when affected workloads improve repeatedly by at least 5%,
beyond dispersion. Investigate repeatable regressions above 3% and any material
increase in direct compilation time. Record rejected experiments too.

## Measurement

Freeze the starting compiler and standard library before each experiment. The
first batch starts at `d9a9f90`; the small-loop batch starts at `ce282be`.
Do not combine ratios or absolute timings across these separate cohorts.
The October 26 results locate slow workloads; they are not a baseline for this
machine or compiler.

Use the same toolchain, sources, inputs and host for baseline and candidate.
Qualify both official LangArena profiles on both engines, retain cold build and
engine startup measurements, and compare interleaved runtime samples:

```sh
python bench/langarena.py measure --tracks adapted --backends direct \
  --goose /path/to/baseline/bin/goose --skip-edits \
  --compile-samples 5 --runtime-samples 5 \
  --output-dir build/performance/baseline
python bench/langarena.py measure --tracks adapted --backends direct \
  --skip-edits --compile-samples 5 --runtime-samples 5 \
  --output-dir build/performance/candidate
python bench/compare_runtime.py build/performance/baseline/report.json \
  build/performance/candidate/report.json --samples 5 \
  --output-dir build/performance/paired
```

The paired harness checks workload, standard-library, runner and engine
identities, rechecks every official checksum, and shuffles variant order within
each task/engine pair. It also interleaves five complete cold builds per cell
and verifies that their modules match the qualified artifacts byte for byte.
It retains raw timings, MAD, artifact hashes, commands,
output and engine compilation/instantiation time. Other activity on a shared
desktop can still affect results.

The full default differential suite is the final correctness gate. Focused
cases cover integer widths/extremes, negative remainders, single evaluation,
condition ordering, wrapping and lazy trapping/side-effecting branches.

## V8 tiering diagnosis

The original direct sieve module takes 15.06/15.78 seconds with default V8
settings and 1.77/1.79 seconds with `--no-liftoff --no-wasm-tier-up`. Every run
passes the official production checksum. This is a diagnostic on the same
immutable module, not a backend optimization or a replacement benchmark mode.

Goose has inlined the warmup and measured kernels into one `main` invocation.
V8 has no Wasm on-stack replacement: a call started in Liftoff finishes there
even if optimized code becomes available. Warmups inside that invocation do
not reenter its optimized replacement. See the
[V8 compilation pipeline](https://v8.dev/docs/wasm-compilation-pipeline).

Astra proposed a separate experiment: retain ordinary loop-containing callees
at repeated call sites in the direct target. It preserved explicit inline
functions and complex captured/owned/nonlocal signatures, and left native/C-Wasm
inlining unchanged. This supplied real engine reentry without changing runner
flags or the workload algorithm.

**Rejected as the default.** Five interleaved pairs measured an 8.50× V8 sieve
speedup but a 0.788× Wasmtime speedup: roughly 27% longer execution. Its hot
fill, marking and counting loops have identical Wasm instructions and bounds
checks. Added Goose checks do not explain the regression; its engine-level cause
remains unresolved. The final compiler retains the original inlining policy.
