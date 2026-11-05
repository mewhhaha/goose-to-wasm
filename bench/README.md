# Reproducible backend measurements

Run the frozen source and output contracts before collecting performance results.
Then, with a native C compiler, Node and Wasmtime installed:

```sh
python3 bench/benchmark.py
```

The default run builds each workload five times with each backend and collects
seven runtime samples for every backend/engine combination. It writes
`build/benchmark/report.json`, `report.md`, exact commands, and per-sample output.
The JSON preserves every measurement, hashes, flags, versions, workload input,
checksum, sample count, median, MAD, quartiles, minimum, and maximum.

| Backend | V8 | Wasmtime | Native process |
| --- | --- | --- | --- |
| Direct binary Wasm | Yes | Same module | — |
| Goose C through native C compiler | — | — | Yes |

Direct output uses memory32. Historical C-to-Wasm measurements used the earlier
C++ compiler and memory64; they remain in dated evidence. The current compiler
supports direct Wasm and native C.

## What is measured

**Complete cold build:** a fresh driver process with `--no-cache`, including the
Goose frontend, emission, and any C compilation/linking. The OS page cache is
retained. “Cold” here does not
mean a reboot or flushed filesystem cache.
Direct uses the same Goose `-O2` semantic passes as the C targets and emits
binary Wasm directly. The C targets additionally run their compiler's `-O2`.
Per-phase driver timings accompany wall time, so wrapper overhead is visible.

**Timed runtime region:** an input-dependent kernel between two monotonic clock
calls. Input parsing, engine startup, compilation/instantiation, and formatting
are outside this region. Two full kernel executions in the same process warm
engine code before the measured execution. An input barrier makes the workload
opaque to optimizers, and a sink consumes its result before the final clock.
The region includes those two scalar FFI barriers and the clock-call boundary.
No Python callbacks occur inside a kernel's computational loop.

**Process wall time:** launching the program/host, engine work, warmup kernels,
measured kernel, formatting, and teardown. This is reported separately; it must
not be described as kernel time. Outer warmup processes prime system caches,
while the within-process warmups are what warm the current Wasm engine instance.

Workload inputs are read from stdin, never embedded as compile-time constants.
Every result is checked against an independent Python reference computation
outside the measured region. A wrong result or failed build makes the report
fail. Compilation and runtime sample orders are deterministically shuffled.

## Workloads and controls

The fixtures cover a dependent integer recurrence with remainder, recursive
Fibonacci, an ordered float recurrence, and indexed updates to a fixed array.
These deliberately bounded scalar/linear-memory kernels exercise the direct
backend's supported fragment. They are not a whole-language performance claim.
Fibonacci is particularly sensitive to recursive-call transformations and
repeated-subexpression elimination by the backend compiler. Its timings measure
the optimized whole computation, not the cost of an individual function call.

```sh
# Correctness/CI smoke only: these tiny workloads cannot rank performance.
python3 bench/benchmark.py --smoke --samples 2 --compile-samples 1 --warmups 1

# Isolate a workload, or select explicit tool executables.
python3 bench/benchmark.py --workloads integer_mod \
  --goose build/bin/goose --emcc /path/to/emcc --cc gcc --node node
```

`--kernel-warmups` controls the untimed executions inside each process;
`--warmups` controls untimed whole-process samples. Both default to two.
`--samples`, `--compile-samples`, `--backends`, `--engines`, and `--output-dir`
make reduced or repeated runs explicit. Fewer than five samples and timed
regions below 10 ms are marked as limitations in the generated report.

Keep the system quiet during measurement. Report the machine and tool versions
alongside comparisons. Engine tiering, compiler optimizations, CPU frequency,
host-boundary costs, and background load affect results. A result from this
suite does not justify a universal claim that one backend is faster.

Unchanged-build and edited-source measurements belong to
`bench/incremental.py`; they use a separate contract and report.

## Paired compiler changes

`compare_runtime.py` compares direct-Wasm artifacts from two qualified LangArena
reports. It interleaves complete builds and runtime pairs, checks source/engine
identities and official checksums, and retains raw timings plus startup data.
Use `--compile-samples 0` to compare preserved artifacts when the original
compiler executables are unavailable. See the
[runtime work and reproduction commands](../docs/RUNTIME_PERFORMANCE.md).

## Snapshot 40 results

The [dated example results](results/2026-11-05/names-and-enums/README.md) record the compiler, workload, toolchain and engine identities, raw measurements and limitations. The native column uses this compiler's C backend. Sorting took 161.7 ms with minimal AOT and 112.6 ms natively. Snapshot 39 was measured separately; these runs do not establish a matched runtime improvement.

## Example programs

The [example benchmark guide](examples.md) covers fresh-process builds and execution of the ten example programs.

## LangArena workloads

The [LangArena guide](langarena/README.md) describes a second harness with the
complete pinned 50-task catalog, official small and production inputs, and
seven explicitly adapted ports. It measures the original whole application
separately from the common ports. Every build failure and unsupported target
remains visible; every successful runtime must pass its official checksum.

```sh
python3 bench/langarena.py fetch
python3 tests/test_langarena.py
python3 bench/langarena.py check --emcc /path/to/emcc
python3 bench/langarena.py measure --emcc /path/to/emcc \
  --machine-label "observed machine description"
```

This harness uses each upstream workload's own warmup and state rules. It does
not apply the microbenchmark harness's fixed two-call warmup. Actual marker-edit
rebuilds are required by default, while unchanged cache hits are an optional,
separate phase. The initial three-sample measurement is preliminary and reports
raw values and dispersion.

## Fibonacci optimization diagnostic

```sh
python3 bench/fibonacci_diagnostic.py --samples 7
```

This diagnostic independently varies Goose and GCC optimization levels, with
the host timing shim compiled at GCC O2 in every cell. It retains generated C,
recursive inlining reports, optimized GCC IR, and disassembly alongside verified
runtime-input measurements. The [retained follow-up](results/2026-10-26/fibonacci-followup/README.md)
explains the native result and its limits.
