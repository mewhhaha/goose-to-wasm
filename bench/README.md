# Reproducible backend measurements

Run the semantic differential suite before collecting performance results. Then,
with the pinned native compiler, Emscripten, Node, and Wasmtime installed:

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
| Goose C through Emscripten | Yes | Same standalone memory64 module | — |
| Goose C through native C compiler | — | — | Yes |

Both Wasm hosts implement the direct scalar host contract and the small WASI64
service contract used by the standalone C oracle. The C oracle's LP64 pointers
require 16-byte WASI iovecs; this host is deliberately not an ordinary WASI32
runtime. Direct output uses memory32. This layout difference is part of the
compared targets. The computational loops execute entirely in WebAssembly.

## What is measured

**Complete cold build:** a fresh driver process with `--no-cache`, including the
Goose frontend, emission, and any C compilation/linking. The OS page cache is
retained, as is Emscripten's installed system-library cache. “Cold” here does not
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
