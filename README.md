# Goose to Wasm

A direct WebAssembly backend for the real [Goose compiler](https://github.com/aardappel/goose),
with native C and C-to-Wasm reference pipelines, differential tests, and reproducible
compile-time and runtime measurements. The target engines are **V8 and Wasmtime**.

The direct path reuses Goose's parser, resolver, type checker, specialization,
optimizer, and bounds analysis. It emits binary WebAssembly directly from the
checked program. It does **not** generate C, invoke Clang/Emscripten, or run an
assembler when compiling a Goose program. A small binary writer is part of this
repository. The compiler itself is built as a native C++ executable.

The direct target supports scalar functions, recursion, control flow, fixed and
dynamic owned arrays, structs, enum payloads, owned aggregate returns, slices,
references, and string builders. It includes checked allocation, ownership
cleanup, a resident native compiler for edit loops, and a qualified Linux
package. Unsupported constructs produce compile errors with no C fallback.
**This is a defined supported target, not full Goose language parity.** Threads,
pool references, runtime closures, and several other constructs remain outside
[the target contract](docs/TARGET.md). See [release qualification](docs/RELEASE.md)
for the tested deployment scope and remaining work.

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

[examples/dynamic_values.goose](examples/dynamic_values.goose) demonstrates
owned enum results, deep copies, string construction, and a reference that
survives array growth. Compile it with the same commands and a different output
name.

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

For repeated edits, start `python scripts/goose_wasm.py serve`. The server keeps
a native compiler process alive and accepts one JSON build request per line.
An actual edit still runs the complete frontend and emitter; unchanged-cache
hits are reported separately. [Server protocol and build guarantees](docs/INCREMENTAL.md).

To create and verify an installable Linux compiler bundle:

```sh
python scripts/package_release.py
python tests/test_package.py
```

The archive includes `bin/goose`, a `bin/goose-wasm` driver, the standard library,
both engine hosts, source, licenses, and a SHA-256 file manifest. Packaging rejects
stale compiler/header/patch/source combinations. CI publishes the same bundle
after qualification.

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
host. `-O0`, `-O1`, and `-O2` select Goose optimization levels; the C paths also
invoke their C compiler at the corresponding level. The direct target adds
small typed transformations and preserves ordinary loop-bearing function calls
so a tiered Wasm engine can optimize subsequent calls. Native/C-Wasm retain the
upstream inlining policy. Explicit inline and capture/nonlocal-return requirements
remain respected.

## Correctness qualification

```sh
python scripts/check_engines.py --output build/engine-probes.json
python tests/run_differential.py --engines v8 wasmtime \
  --backends direct c-wasm native
python tests/test_backend_extensions.py
python tests/test_dynamic.py --backends native c-wasm direct
python tests/test_variants.py
python tests/test_memory.py
python tests/test_runtime_optimizations.py
python tests/test_build_support.py
python tests/test_incremental.py
python tests/test_driver_publication.py --emcc emcc
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
formatting, control flow, recursion, stable references across array growth,
deep copies and cleanup of nested owners, enum payloads, sparse static memory,
concurrent build publication, worker recovery, and target refusals. A refused
program is not counted as a successful execution.

The retained oracle corpus also checks the fixed data-stack runtime, capacity
boundaries, serialization, relative references, builders, and other Goose features
that the new direct backend does not yet implement. Passing that corpus validates
the reference path, not direct-backend coverage.

The C oracle includes a narrowly scoped correction for overlapping append into
limited arrays. The regression has an independently specified result; see
[reference compiler corrections](docs/ORACLE.md) for the pinned upstream defect,
the `memmove` patch, and the retained test.

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
It records whole-suite builds, seven historical bounded adaptations, and a new
track using the **original seven kernel and helper files byte for byte**, including
their dynamic storage. The new track changes only the configuration, entrypoint,
and timing harness. The historical ports remain for comparison with retained
baseline measurements. Sources, input sizes, iteration counts, and expected
checksums are identical across backends within each track.

```sh
python bench/langarena.py fetch
python bench/langarena.py check --emcc /path/to/emcc
python bench/langarena.py measure --emcc /path/to/emcc \
  --machine-label "observed machine description"
python bench/langarena_kernels.py --emcc /path/to/emcc --samples 3 \
  --machine-label "observed machine description"
```

The harness retains all 50 coverage rows, explicit Wasm refusals, complete cold
builds, observable marker-edit rebuilds, computational regions, engine startup,
and process wall times. Wrong checksums fail qualification. These measurements
are local backend comparisons, not published LangArena ranks or a claim of
complete Goose support. Edits still rerun the complete frontend.

The [2026-10-26 gauntlet results](bench/results/2026-10-26/langarena/README.md)
retain all raw evidence. The seven direct cold builds took 73–94 ms each,
8.4–13.3× faster than C-to-Wasm on the same sources. All 50 original native cases
and all seven adapted cases passed their full production checksums. Runtime
results are mixed: hashing and V8's sieve have substantial direct-backend gaps.
Observable direct rebuilds took 61–77 ms and still recompile the whole program.

### Incremental foundation

The current incremental foundation is:

- A content-checked module cache, including resolved imports, symlink targets,
  module-search candidates, compiler identity, flags, and relevant environment.
- A persistent JSON-lines build server and native compiler worker that avoid
  Python/native process startup on repeated requests and revalidate source
  contents and the import namespace before publishing a module.
- Per-function bytecode fingerprints and call dependencies in compiler statistics,
  providing a concrete basis for a future function cache.

**Edits currently rerun the entire frontend and emitter.** The function hashes
measure unchanged output; they do not skip function compilation. Unchanged-build
cache hits and edited builds are reported as separate measurements. See
[incremental architecture](docs/INCREMENTAL.md).

```sh
python scripts/goose_wasm.py serve
```

Each stdin line is a request, and each stdout line is a response:

```json
{"id":1,"args":["build","examples/squares.goose","--backend","direct","-o","build/squares.wasm"]}
```

`--no-cache` forces full compilation. A failed compile leaves the previous output
intact. `--stats FILE` writes driver timings and backend statistics as JSON.

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
