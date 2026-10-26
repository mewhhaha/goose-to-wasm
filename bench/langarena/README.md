# Pinned LangArena gauntlet

This integration keeps the complete **50-task catalog** from
[kostya/LangArena](https://github.com/kostya/LangArena) at commit
`aab9b14998231ba905523b5ba3990ee03c46f64d`. The official `test.js` and `run.js`
configuration files are retained byte for byte as `test.json` and `run.json`.
`manifest.json` records every task, both official configurations, source hashes,
port bounds, and the exact upstream revision. The upstream MIT notice is in
[UPSTREAM_LICENSE](UPSTREAM_LICENSE).

## Two explicit tracks

**Whole original suite.** Build the original Goose entrypoint and all 50 kernel
sources with each backend. A private source copy changes only the marker output
path, from `/tmp/recompile_marker` to `recompile_marker` in that execution's
isolated directory. The pinned checkout and any preexisting `/tmp` marker are
never changed. The native executable must pass all 50 official small cases and
all 50 production cases. Whole-suite Wasm compilation refusals remain visible.
The current profiles refuse dynamic storage in the direct suite and reachable
threads/queues in the C-Wasm suite. A refusal receives no successful compile-time
score.

**Seven adapted entrypoints.** The same port source is compiled as native C,
C-Wasm, and direct Wasm. Each Wasm binary runs unchanged on V8 and Wasmtime.
Fannkuch retains its original fixed-array kernel and changes the harness only;
the other six ports replace growable storage with declared bounds. They are
identified as adaptations throughout the report. They do not establish that
the original whole suite runs on Wasm.

| Upstream task | Ordered runtime parameters | Bound |
| --- | --- | --- |
| `CLBG::Fannkuchredux` | `n` | 1–32; official values 5 and 8 |
| `Etc::Sieve` | `limit` | 2–3,000,000 |
| `Sort::Quick` | `size` | 1–400,000 |
| `Sort::Merge` | `size` | 1–400,000 |
| `Hash::SHA256` | `size` | 1–1,000,000 |
| `Hash::CRC32` | `size` | 1–1,000,000 |
| `CLBG::Mandelbrot` | `w`, `h` | Each 1–400; at most 120 total warmup + measured executions |

`Hash::SHA256` is the upstream task name for its **custom hash**; the workload
does not implement standard cryptographic SHA-256. See
[port details](ports/README.md) for storage and algorithm notes.

The three threaded matrix cases are neither replaced with sequential kernels
nor counted as supported Wasm executions. All 43 tasks without an adapted
entrypoint remain in the catalog and coverage denominator.

## Reproduce

Install the compiler and pinned engines using the repository bootstrap first.
Fetch the upstream inputs before measuring; dependency downloads are excluded:

```sh
python3 bench/langarena.py fetch
python3 bench/langarena.py catalog
python3 tests/test_langarena.py

# Official small inputs, all available backend/engine cells, and marker checks.
python3 bench/langarena.py check --emcc /path/to/emcc

# Also qualify the full production inputs once, without performance claims.
python3 bench/langarena.py check --profiles test run --skip-edits \
  --emcc /path/to/emcc --output-dir build/langarena-qualification

# Full measurement: 3 cold builds, 3 actual-marker rebuilds, 3 runtime samples.
python3 bench/langarena.py measure --emcc /path/to/emcc \
  --machine-label "observed machine description"
```

An existing verified checkout can be supplied with `--upstream /path/to/LangArena`.
`check` and `measure` do not fetch sources or bootstrap missing compilers.
Use the Python environment containing the pinned Wasmtime bindings. Explicit
`--goose`, `--cc`, and `--node` paths select the measured tools.

The measured workspace uses the installed Node 24.22.1 executable for both the
V8 host and Emscripten's helper processes. Its SDK-bundled Node crashed during
setup; the override is recorded in every report:

```sh
mkdir -p build/em-cache build/tmp
export EM_NODE_JS="$(command -v node)"
export EM_CACHE="$PWD/build/em-cache"
export TMPDIR="$PWD/build/tmp"
export EMCC_CORES=2
```

`--filter` selects task names without changing the 50-task coverage denominator.
`--tracks whole` or `--tracks adapted` focuses a track. `--backends` and
`--engines` restrict execution cells. `--profiles test run` is required for
production runs: the corresponding small-case checksum must pass first.
`--compile-timeout` and `--run-timeout` bound each child process, defaulting to
600 seconds. Failed checks, compiler errors, and timeouts remain in the report.

Increase `--compile-samples` and `--runtime-samples` for stronger measurement
estimates. The three-sample default is explicitly preliminary. `--noop` adds
unchanged direct cache hits as a separate phase, including a separate cache
priming build; it does not replace the actual source-edit measurements.

## Input, state, and checksum contract

Every port reads its listed parameters from stdin, followed by `iterations`
and `warmups`. For example, production Mandelbrot receives:

```text
400 400 100 20
```

Every successful port prints exactly two decimal lines: the official checksum
and the elapsed nanoseconds. No parameters or expected checksum are compiled
into the workload as substitutes for runtime computation.

Preparation stays outside the clock. Warmup calls mutate the **same state** used
for measured calls. The helper RNG is reset before preparation and again before
measurement; benchmark state is not reconstructed after warmup. This matters:
small Sieve's checksum includes three measured calls plus its one warmup call.
Mandelbrot preserves every appended PBM image, including warmups, and hashes the
complete output after the clock. Existing in-kernel checksum work stays inside
the measured region where upstream places it.

The harness derives default warmups using the upstream rule
`max(trunc(iterations * 0.2), 1)`, retaining explicit overrides. Official inputs
and expected checksums are checked against the pinned configuration hashes.
Wrong checksums never produce passing performance rows.

## Compilation and timing contract

Whole-suite compilation is the complete 50-task program. Per-port compilation
is a different compilation unit and is reported separately. Cold builds and
actual-marker builds use fresh driver/compiler processes with `--no-cache`.
OS page caches and installed compiler/system-library caches are retained.
Source generation and dependency fetching happen before timed builds.

The original marker edit changes the string written by the program from
`RECOMPILE_MARKER_0` to `RECOMPILE_MARKER_1`. The edited executable must write
the new value in its private run directory. Each port's marker changes
`let ARENA_REVISION = 0;` to `let ARENA_REVISION = 1;`; after printing its unchanged
checksum and duration, it exits with that revision. The harness requires exit
1 only for that edited variant, verifies the official checksum, and verifies
that the artifact bytes changed. Source bytes are restored even after failure.

Edited programs still run the complete frontend and emitter. An optional
unchanged disk-cache hit is labeled separately and must report a real cache hit.
It is not LangArena's incremental marker-edit compilation measurement.

Runtime preparation and warmup are excluded from each in-program clock.
Whole-suite runs start a separate process for every task, as upstream's global
runner does. Port processes also begin with fresh state and execute the official
warmup before timing. Input parsing, engine initialization, output formatting,
and shutdown remain visible in separate process wall times. The upstream timer
prints only three decimal places in seconds; port timers retain nanoseconds.
The Wasm runners additionally record engine compilation/instantiation and entry
function time. Entry-function time includes preparation and warmup; it is
distinct from the port's timed computational region.

Build and runtime order are deterministically shuffled. Samples execute
sequentially so the harness does not deliberately create compiler contention.
The JSON preserves raw observations, median/MAD, quartiles, min/max, commands,
stdout/stderr, official inputs, environment overrides, tool versions, source
hashes, artifact hashes, driver phase timings, and the complete coverage matrix.
Changing the compiler or measured sources during a run invalidates its status.
The consolidated JSON is checkpointed atomically after every completed
observation and stays marked `incomplete` until the run finishes. Cancellation
terminates active child-process groups, restores edited markers, and marks the
partial report `interrupted`. A hard process kill still leaves the preceding
atomic checkpoint and per-command logs.

## Interpretation

Compare backend timings within the same track and source. Comparing an original
growable-storage native workload with a fixed-storage direct port would also
measure the storage adaptation. Allocation behavior and representation are part
of the stated experiment.

Local timings are not published LangArena ranks. Its October 2026 leaderboard
uses another machine, Goose revision, Clang/GCC versions, target configurations,
and nine weighted ranking metrics. Its compile component uses an actual
marker-edit rebuild. We report our whole builds, source edits, optional unchanged
cache hits, and seven adapted kernels separately, with all unsupported tasks
visible. Passing the seven ports does not establish full-language compatibility.
