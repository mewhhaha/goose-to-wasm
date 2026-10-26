# Release qualification and deployment

This repository supplies a direct compiler with a defined, tested target
contract. Its qualification covers Linux x86-64 builds, Node/V8 and Wasmtime at
the versions in `toolchain.json`, and the explicitly supported Goose features
in [TARGET.md](TARGET.md). It does not establish full Goose parity or guarantee
that an arbitrary upstream program compiles. In particular, the complete
50-task LangArena application still reaches unsupported features. Keep those
refusals distinct from the seven original kernels and historical adapted ports.

## Build and package

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt cmake==4.4.4 ninja==1.13.2
python scripts/bootstrap.py --generator Ninja --jobs 2
python scripts/package_release.py
python tests/test_package.py
```

The package is `build/goose-to-wasm.tar.gz`. It contains a native compiler, its
standard library, the Python driver and native-worker protocol, both engine
runners, examples, documentation, license notices, and corresponding source.
The compiler does not need a C compiler, assembler, Emscripten, network access,
or a Wasm engine to emit a direct module. Python 3.10+ runs the optional driver.
Executing a module requires a compatible host; the supplied V8/Wasmtime hosts
implement the explicit ABI in TARGET.md.

Packaging verifies the built executable's hash, pinned upstream commit, managed
source fingerprint, embedded C runtime, installed standard library, backend
headers, and patches. It refuses an artifact whose compiler is stale relative
to those inputs. `BUILD.json` records the compiler/source identities and whether
the integration checkout was modified, plus the Linux shared-library and symbol
versions required by the executable. `MANIFEST.json` records each packaged
file's SHA-256, byte count, and mode. Archive ordering, ownership, modes, gzip
metadata, and timestamps are deterministic for identical inputs;
`SOURCE_DATE_EPOCH` selects the timestamp (default zero). Native executable
reproducibility across different build environments is a separate property.

The consumer test extracts into a separate directory, verifies every manifest
entry, clears `PATH`, disables C-toolchain discovery, compiles a program that
imports `std`, and executes it on both engines. It also checks the packaged
driver's default compiler/stdlib paths. The Linux compiler still requires its
normal host system libraries; older Linux distributions may need to rebuild
the bundled source. `readelf` (from binutils) is required when creating the
package so these ABI dependencies can be recorded. The source can be rebuilt
without Git or fetching:

```sh
cmake -S source/upstream -B rebuilt -DCMAKE_BUILD_TYPE=Release -DGOOSE_BUILTIN_LIBS=
cmake --build rebuilt --parallel 2
```

Other operating systems must build from source;
this package qualification does not certify them.

## Gates

The GitHub Actions workflow builds from immutable source and SDK pins. It then
runs the existing portability oracle, direct/native/C-Wasm differential tests,
owned aggregate and scalar-math tests, dynamic ownership/string/enum tests,
numeric optimization tests, memory-limit and sparse-data tests, driver and
worker tests, LangArena contracts and small cases, and the extracted-package
test. Reports and the bundle are uploaded as one qualification artifact.

The dynamic tests exercise multiple chunks and a growing chunk table, retained
references/slices, large elements, nested deep copies, returned owners, repeated
temporary reuse, and resource exhaustion. Optimizations are checked at O0/O2
and in debug builds where checked arithmetic changes legal transformations.
The native and C-Wasm paths remain independent code-generation oracles. A
refusal is evidence of a boundary, not a passing execution.

Full-production-input performance runs are retained separately from CI's small
correctness cases. They preserve official inputs, warmup state, checksums,
compiler/host hashes, raw samples, and measurement dispersion. They are local
comparisons rather than published LangArena ranks. Use the command lines in the
retained report to reproduce a result; the two LangArena storage tracks measure
different programs and must not be combined in one speedup ratio.

## Fast compilation and remaining work

Direct emission avoids C/LLVM startup and optimization. Sparse data avoids
serializing zero-filled storage. A resident native worker reduces per-edit
process/thread startup. Small, bounded code-generation transformations improve
execution without adding a heavyweight optimization pipeline. The direct
target also preserves ordinary loop-bearing calls so V8 can use optimized code
on later invocations; it does not change V8 flags or depend on Wasm OSR.

Every actual edit still runs the complete frontend and emitter. The module
cache only skips that work for unchanged, content-validated inputs. Function
fingerprints are measurement data, not a semantic incremental compiler. A
future incremental frontend needs stable declaration identities, dependency
tracking for name/type/specialization changes, and a correct invalidation model.

The remaining language work is listed explicitly in TARGET.md. Additional
production work includes more real-application corpus coverage, allocator and
slice-access performance, finer-grained lifetime cleanup, a maintained
compatibility policy for the host ABI, and qualification on other platforms.
Treat this release as a qualified compiler for its documented contract, with
the benchmark and test evidence available for inspection; do not interpret the
word "production" as a claim that these remaining areas are complete.
