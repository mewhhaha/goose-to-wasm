# Goose to Wasm

A direct WebAssembly backend for the real [Goose compiler](https://github.com/aardappel/goose),
with native C and C-to-Wasm reference pipelines, differential tests, and reproducible
compile-time and runtime measurements. The target engines are **V8 and Wasmtime**.

The direct path reuses Goose's parser, resolver, type checker, specialization,
optimizer, and bounds analysis. It emits binary WebAssembly directly from the
checked program. It does **not** generate C, invoke Clang/Emscripten, or run an
assembler when compiling a Goose program. A small binary writer is part of this
repository. The compiler itself is built as a native C++ executable.

This is an explicitly bounded backend. It supports scalar functions, recursion,
control flow, fixed arrays,
static-capacity resizable arrays, struct fields, fixed-mode enums and payload matches, owned fixed aggregate returns,
slices, references, and named growable arrays of supported fixed-layout elements.
Growable owners use stable checked data regions, borrowed calls, independent
by-value parameters and single owned results constructed into named receivers.
General temporary/result channels remain subsequent work. Unsupported constructs produce compile
errors, with no fallback to the C backend. It is not yet full Goose parity; see
[the target contract](docs/TARGET.md) and [next milestones](docs/ROADMAP.md).
The [completion plan](docs/IMPLEMENTATION_PLAN.md) and checked
[capability inventory](docs/capabilities.json) track the remaining work.

## Quick start: direct compilation

Requirements: Git, a C++20 compiler, Python 3.10+, CMake 3.27+, Ninja (or another
CMake generator), and Node 24.22.1 for the V8 runner. To reproduce the qualified
Python/build-tool versions:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt cmake==4.4.4 ninja==1.13.2
python scripts/bootstrap.py --generator Ninja --jobs 2

python scripts/goose_wasm.py build examples/squares.goose \
  --backend direct -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
python scripts/run_wasmtime.py build/squares.wasm
```

Both engines print:

```text
sum=140
```

The pinned host versions are Node **24.22.1** (V8 **13.6.233.17-node.58**) and
Wasmtime's Python package **50.0.1**. `toolchain.json` records every upstream/SDK
pin. Bootstrap downloads one immutable Goose revision, applies the reviewable
patches, copies `compiler/*.h`, and builds `build/bin/goose`. It verifies managed
sources before refreshing them and preserves manual edits rather than silently
overwriting them.

For the smallest invocation overhead, use the native compiler directly:

```sh
build/bin/goose examples/squares.goose --target wasm-direct \
  -O2 -o build/squares.wasm --wasm-stats build/squares.stats.json
```

The Python driver adds dependency caching, output preservation, and a common
interface to the reference pipelines. Direct compilation needs no Emscripten
installation. A qualification test runs it with an empty `PATH` and unavailable
C-compiler paths.

## The three compilation paths

| Driver backend | Pipeline | Output |
| --- | --- | --- |
| `direct` | Goose frontend → direct binary emitter | `.wasm`, with explicit scalar host imports |
| `native` | Goose frontend/C backend → native C compiler | Native executable |
| `c-wasm` | Goose frontend/C backend → Emscripten | Standalone memory64 `.wasm`, or Emscripten `.mjs` plus `.wasm` |

Install the oracle SDK only when using C-to-Wasm or running the complete tests:

```sh
python scripts/install_emsdk.py --jobs 2
. build/emsdk/emsdk_env.sh

python scripts/goose_wasm.py build examples/squares.goose \
  --backend native -o build/squares-native
python scripts/goose_wasm.py build examples/squares.goose \
  --backend c-wasm -o build/squares-c.wasm

./build/squares-native
node scripts/run_wasm.mjs build/squares-c.wasm
python scripts/run_wasmtime.py build/squares-c.wasm
```

The standalone oracle is the same binary on both engines. It uses an explicit
LP64/WASI64 host adapter in the supplied runners; it is not an ordinary WASI32
command. Its runtime workloads execute in Wasm, while the adapters implement
boundary services such as stdin/stdout and clocks. The `.mjs` oracle retains the
previous Emscripten integration and its broader portability corpus.

`--c-source`, `--c-include-dir`, and `--include` supply C extern implementations
for the reference paths. Direct scalar externs are `env` imports supplied by a
host. `-O0`, `-O1`, and `-O2` select the same Goose semantic optimizations on all
paths; the C paths additionally invoke their C compiler at the corresponding
optimization level.

## Correctness qualification

```sh
python scripts/check_engines.py --output build/engine-probes.json
python tests/run_differential.py --engines v8 wasmtime \
  --backends direct c-wasm native
python tests/test_backend_extensions.py
python tests/test_static_data.py
python tests/test_regions.py
python tests/test_dynamic_boundaries.py
python tests/test_incremental.py
python tests/test_input_dependencies.py
python tests/test_compiler_session.py
python tests/test_lexical_cache.py
python tests/test_syntax_cache.py
python tests/test_syntax_importer.py
python tests/test_checked_leaf_cache.py
python tests/test_checked_scalar_cache.py
python tests/test_checked_leaf_ownership.py
python tests/test_langarena.py

python oracle/tests/test_bootstrap.py
python oracle/tests/test_target.py
python oracle/tests/test_driver.py
python oracle/tests/run_tests.py --full --jobs 2
```

The differential harness checks stdout, exit status, selected diagnostics, and
independently derived answers. Native C supplies an independent reference; both
Wasm backends execute on both engines. Tests cover optimization levels O0/O2,
numeric edge cases, narrow integer wrapping, checked arithmetic/casts, floating
formatting, control flow, recursion, references, aggregate operations, and target
refusals. A refused program is not counted as a successful execution.

The retained oracle corpus also checks the fixed data-stack runtime, capacity
boundaries, serialization, relative references, builders, and other Goose features
that the new direct backend does not yet implement. Passing that corpus validates
the reference path, not direct-backend coverage.

Direct modules omit zero-filled static storage from their data segments while
preserving its addresses and memory limits. On the seven adapted LangArena
entrypoints, this reduces six modules from 1.0–4.8 MB to 3.2–6.6 KB. All seven
pass the official small-input checks on V8 and Wasmtime. See the
[artifact-size comparison](bench/results/2026-10-30/README.md); this measures
file size, not execution speed or a reduction in runtime memory.

GitHub Actions builds from the immutable inputs, executes qualification, runs
benchmark correctness smoke tests, and publishes reports plus the compiler and
its corresponding source.

## Compilation speed and incremental work

```sh
python bench/benchmark.py
python bench/incremental.py
```

The [benchmark guide](bench/README.md) defines cold build, timed kernel, and
process wall time separately. Runtime inputs prevent whole-program constant
folding; every sample must match an independent checksum. Results retain raw
samples, median, dispersion, flags, tool versions, compiler hashes, and engine
identities. The native/C-Wasm paths benefit from C/LLVM optimizations; direct
emission does not promise faster program execution.

### Measured baseline (2026-10-26)

Five complete uncached builds per cell on an AMD EPYC 9V74 KVM guest, using the pinned toolchain. Values are median wall milliseconds, including Python driver startup:

| Workload | C → native | C → Wasm | Direct Wasm |
| --- | ---: | ---: | ---: |
| Integer recurrence | 250.8 | 663.0 | 56.8 |
| Recursive Fibonacci | 276.6 | 638.3 | 58.2 |
| Float recurrence | 257.5 | 592.0 | 56.4 |
| Fixed-array updates | 246.7 | 635.6 | 58.5 |

Direct builds were 10.5–11.7× faster than C-to-Wasm on these four inputs. Runtime results depend on the workload and engine; the full table includes a large native-GCC optimization advantage on recursive Fibonacci. [Measurements, raw samples, and qualification evidence](bench/results/2026-10-26/README.md) record the exact source/tool hashes and limitations.

The [Fibonacci follow-up](bench/results/2026-10-26/fibonacci-followup/README.md)
separates Goose and GCC optimization levels. GCC recursively inlines the
Goose-optimized function, shares overlapping recursive results, and introduces
an accumulator loop. This sharply reduces the computation performed; its speedup
is specific to that redundant recursive workload. Generated C, GCC optimization
reports, assembly, and the four-way experiment are retained.

A separate 32-function `-O0` experiment measured 8.84 ms for a raw compiler invocation, 2.12 ms for an unchanged persistent-server request, and 15.08 ms after a one-function edit. Edits still compile the entire program. [Full rebuild measurements](bench/results/2026-10-26/incremental.md).

### LangArena gauntlet

The [LangArena integration](bench/langarena/README.md) pins the complete
50-task upstream Goose suite and its official test/production configurations.
It records whole-suite builds separately from seven adapted entrypoints that
can run across all three backends and both Wasm engines. Fannkuch keeps its
fixed-array kernel; six ports replace growable storage with disclosed bounds.
The adapted sources, input sizes, iteration counts, and expected checksums are
identical across the compared backends.

```sh
python bench/langarena.py fetch
python bench/langarena.py check --emcc /path/to/emcc
python bench/langarena.py measure --emcc /path/to/emcc \
  --machine-label "observed machine description"
```

The harness retains all 50 coverage rows, explicit Wasm refusals, complete cold
builds, observable marker-edit rebuilds, computational regions, engine startup,
and process wall times. Wrong checksums fail qualification. These measurements
are local backend comparisons, not published LangArena ranks or a claim of
complete Goose support. Those edited builds reran the complete frontend.

The [2026-10-26 gauntlet results](bench/results/2026-10-26/langarena/README.md)
retain all raw evidence. The seven direct cold builds took 73–94 ms each,
8.4–13.3× faster than C-to-Wasm on the same sources. All 50 original native cases
and all seven adapted cases passed their full production checksums. Runtime
results are mixed: hashing and V8's sieve have substantial direct-backend gaps.
Observable direct rebuilds took 61–77 ms and still recompile the whole program.

### Incremental foundation

The current incremental foundation is:

- A content-checked module cache, including parsed configurations, resolved
  imports, missing-path probes, symlink targets, module-search candidates,
  compiler identity, flags, and relevant environment.
- A persistent JSON-lines build server that avoids Python startup on repeated
  requests and validates source content before reusing a module.
- An optional native worker with source overlays and bounded parsed-module
  reuse, importing syntax into a fresh request AST.
- Per-function bytecode fingerprints and call dependencies in compiler statistics,
  providing a concrete basis for a future function cache.

**Edits still rerun resolution, caller checking, optimization, and emission.** An
optional checked caches skip unchanged closed scalar leaves and restricted callers.
The function hashes measure unchanged output; they do not skip function emission. Unchanged-build
cache hits and edited builds are reported as separate measurements. See
[incremental architecture](docs/INCREMENTAL.md).

```sh
python scripts/goose_wasm.py serve
```

Each stdin line is a request, and each stdout line is a response:

```json
{"id":1,"args":["build","examples/squares.goose","--backend","direct","-o","build/squares.wasm"]}
```

Use `serve --native-worker` to retain the native compiler process too. This
mode also accepts a `sources` object mapping existing absolute file paths to
unsaved source text. Each request supplies the complete overlay set; omitting
it restores disk contents. Overlay builds bypass the disk module cache and do
not modify source files. New virtual files are not supported by import discovery.

The native worker owns a fresh compilation AST for every changed build.
Add `--syntax-cache` to reuse unchanged files' parsed syntax while rebuilding
all semantic results. `parsed_files` and `parsed_cache_hits` expose actual
parsing and reuse; no checked syntax survives into the next request.
`python tests/test_compiler_session.py` checks request isolation, module
equivalence, recovery, aliases, process restart, and retained memory.
`tests/test_syntax_cache.py` checks cache invalidation and context;
`tests/test_syntax_importer.py` destroys templates before checking/emitting
their imported syntax under sanitizers. Compare session timings with
`python bench/incremental.py --native-worker`, adding `--syntax-cache` to
measure parsed-module reuse.
The retained [O0/O2 syntax-cache comparison](bench/results/2026-10-30/syntax-cache.md)
shows less parsing but no established edited-build wall-time improvement.

Add `--checked-leaf-cache` to reuse checked numeric/bool leaf functions with one
explicit scalar result and explicitly typed scalar parameters. Their bodies may
contain arithmetic, parameter reads, conditionals, blocks, and local returns.
Calls, globals, captures, locals, loops, explicit casts, generic functions, and
aggregate/reference types recheck normally. Entries contain values and indices;
each request recreates its own nodes, types, parameters, and source origins.
`checked_leaf_cache_hits` counts skipped body checks, and `semantic_reused`
records this limited reuse. Caller overload resolution and all later passes
still run. Compare this mode using `bench/incremental.py --shape leaves
--native-worker --syntax-cache --checked-leaf-cache`.
The [retained comparison](bench/results/2026-10-30/checked-leaves.md) shows
smaller type-check phase medians and mixed O2 edited-build wall times.

Use `--checked-scalar-cache` to include a restricted class of scalar callers.
These have canonical `i64` signatures and one straight-line arithmetic result;
direct named callees must resolve uniquely, and call arguments must be parameter
identifiers. Every request revalidates the closed, acyclic source graph and
binds current callee specializations. Editing a callee's body can therefore
preserve its callers' checked arithmetic while optimization sees the new body.
`checked_scalar_caller_hits` counts those reused callers. Overloads, namespace
shadowing, changed signatures, effects, or excluded syntax trigger normal
checking. This option includes the leaf support and supersedes
`--checked-leaf-cache` when both are selected.
The [chain comparison](bench/results/2026-10-30/checked-callers.md) verifies
31 reused callers but does not establish an end-to-end speedup.

`--no-cache` disables whole-module artifact reuse; explicitly enabled native
syntax/token caches remain active. A failed compile leaves the previous output
intact. `--stats FILE` writes driver timings and backend statistics as JSON.
Unsaved overlays and `--no-cache` retain publication guards while skipping
extra disk-cache validation. Benchmark unsaved edits with
`--edit-source-mode overlay`; disk edits remain the benchmark default.
On the retained 32-function local comparison, driver changes reduce unsaved-edit
medians from 12.3–14.7 ms to 9.5–10.9 ms. [Raw timings and limitations](bench/results/2026-10-30/driver-overhead.md).

## Source organization

| Path | Purpose |
| --- | --- |
| `compiler/` | Direct binary emitter and AST lowering |
| `patches/direct-target.patch` | Hook into the upstream compiler before C code generation |
| `oracle/` | Checked C runtime patch, Emscripten driver, and retained qualification corpus |
| `scripts/bootstrap.py` | Reproducible compiler build and source verification |
| `scripts/goose_wasm.py` | Common driver, module cache, and persistent build server |
| `scripts/run_wasm.mjs`, `scripts/run_wasmtime.py` | Engine hosts and explicit runtime services |
| `tests/` | Direct/reference comparisons and incremental contracts |
| `bench/` | Runtime-input workloads and reproducible measurement harnesses |

The new backend and upstream Goose source are Apache-2.0 licensed. The retained
oracle integration keeps its [MIT license](oracle/INTEGRATION-LICENSE).
Imported LangArena configurations and adapted kernels retain the upstream
[MIT notice](bench/langarena/UPSTREAM_LICENSE), also included beside the ports.
Bootstrap
packages the upstream runtime/header and bundled dependency notices with the
native compiler. Full native platform packages, a browser-hosted compiler, and
incremental semantic analysis are subsequent work, documented separately from
the implemented target.
