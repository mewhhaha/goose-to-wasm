# Runtime performance work

## Measured gains

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

## Plan

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

The starting compiler is the README revision `d9a9f90`. Preserve its installed
compiler and standard library before rebuilding. The October 26 results locate
the slow workloads; they are not a baseline for this machine or compiler.

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
