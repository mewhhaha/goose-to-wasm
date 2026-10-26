# Fast edit compilation and build publication

## What is implemented

The direct compiler emits binary WebAssembly from Goose's typed and specialized
AST. It does not invoke a C compiler, assembler, or linker. The Python driver
supports two distinct accelerations:

1. A dependency-checked cache returns a complete module when its inputs have not
   changed.
2. A **resident native compiler process** handles changed-source requests from
   the build server. It retains the executable, a 64 MiB compiler stack thread,
   and allocator state across builds. This avoids starting a native process and
   compiler thread for every edit.

Every actual edit still constructs a new AST and runs parsing, name resolution,
type checking, specialization, optimization, bounds analysis, and complete
function emission. No AST, inferred type, specialization, or emitted function
body is reused. This is process/session reuse, **not an incremental type checker
or a function compilation cache**. That distinction also appears in build and
benchmark statistics.

## Using the server

Start a local JSON-lines server:

```sh
python3 scripts/goose_wasm.py serve
```

Send one request per line, with ordinary build arguments:

```json
{"id":"edit-1","args":["build","project/main.goose","-o","build/main.wasm","-O0"]}
```

The response echoes `id`, sets `ok`, and includes either a `result` object or an
`error`. Requests are processed serially. A failed source edit leaves the last
completed output available; the same server can accept a corrected edit.

`--compiler-mode auto` is the default. A command-line build starts an ordinary
native compiler process. A request through `serve` uses the resident compiler
when a direct compilation is needed. `--compiler-mode process` forces a fresh
native compiler for comparison or troubleshooting. `--compiler-mode session`
explicitly requires the native worker, including from a one-shot command;
starting a new worker for each command does not provide its edit-loop benefit.
The session mode applies only to the direct backend.

Use `-O0` to measure or prioritize the fast edit path, and measure `-O2` release
builds separately. `--no-cache` always runs the complete frontend and emitter;
in a persistent server it can still use the already-running native worker.
For a cold compiler-process measurement, combine it with
`--compiler-mode process`, or invoke a fresh ordinary command-line build.

The server is a local process protocol on stdin/stdout, not a network service or
a security boundary. It runs with its caller's filesystem and package access.
The native worker accepts a bounded direct-compilation argument set; it cannot
use its protocol to execute a Goose program, run the C backend, invoke the JIT,
or switch to unrelated compiler commands. It caps request size and JSON nesting.

## Native worker lifetime and isolation

The worker runs its request loop on the compiler's existing guarded 64 MiB
compiler stack. Nested compilation uses that same stack instead of creating a
new thread. Each call to the ordinary compiler driver owns and destroys its
source buffers, AST, definitions, types, diagnostics, specializations, and
backend state before replying.

The mutable frontend globals `package_update`, `package_nofetch`, and diagnostic
`dumpwritten` are reset before every request. Build options are ordinary fresh
local variables. An ordinary parse, type, or unsupported-feature error leaves
the worker usable. An unexpected C++ exception terminates the worker after a
failure response; a later build starts another worker. A worker that exits or
violates its protocol is never used to publish an artifact.

The Python server identifies a worker by compiler path and content hash, working
directory, and its complete inherited environment. It starts a replacement when
that identity changes or the process exits. Optimization, debug, stdlib, and
memory arguments are supplied anew for each compilation. Source content is
never trusted because an editor preserved its timestamp or file size.

`--timeout SECONDS` bounds each compiler/tool invocation and worker response;
its default is 120 seconds. On POSIX, tools and workers have private process
groups so timeout and cancellation terminate descendants as well as the direct
child. `--lock-timeout SECONDS` independently bounds waiting for another writer
of the same output. Native Windows uses file byte locks; its subprocess cleanup
terminates the direct child, without claiming POSIX process-group semantics.

## Dependency and module-cache correctness

A cache identity includes the compiler's SHA-256, source path,
optimization/debug flags, memory settings, working directory, and the relevant
Goose environment. The compiler returns the exact source text it parsed,
including imports. Records preserve hashes of that text, lexical import paths,
resolved symlink targets, and module-search candidates.

A hit rechecks contents, including same-size/same-mtime changes. UTF-8 BOM
normalization matches the frontend. Retargeting a symlink, adding a module that
can shadow another import, or modifying a package `.build` sidecar invalidates
the entry. Directory symlinks are traversed with cycle detection. An unreadable
or broken namespace makes the result uncacheable.

Before a direct compile, the driver snapshots the known module search
namespace. After compilation it checks that every parsed source still matches
the compiler's transcript and compares the namespace again. Discovering a new
external package directory triggers another compile with that directory in the
before-snapshot. A source or namespace change during compilation also retries.
After three unstable attempts, the build fails and preserves the previous
output. A compiler executable that changes during a build also prevents
publication. These checks observe the filesystem at the stated points; they do
not claim an atomic filesystem snapshot against an editor changing files at any
arbitrary instruction between the last check and publication.

The cache stores immutable, content-addressed Wasm blobs and atomically replaces
its metadata record afterward. A reader verifies the blob digest and Wasm
header. Partial, malformed, or corrupted entries are misses. On POSIX, source,
sidecar, and cache reads open without blocking and validate that the opened descriptor
is a regular file; replacing a dependency with a named pipe cannot hang cache
validation. Independent build
processes may safely populate the same cache: a record is validated against its
own dependency snapshot on every hit. A cache write failure is recorded as
`cache_error`/`cache_stored: false`; it does not discard a valid compiler result.

In a source checkout, the default cache is `build/cache`. In a packaged compiler
bundle it is under `XDG_CACHE_HOME/goose-to-wasm`, or
`LOCALAPPDATA/goose-to-wasm` on Windows, with `~/.cache` as fallback. Override it
with `--cache-dir`.

## Output publication and concurrent writers

Builds acquire cross-process locks for their output paths, companion Wasm file,
emitted C, and stats in canonical path order. The lock covers dependency
validation, compilation, and publication. Writers of the same destination
therefore serialize; unrelated output destinations can build concurrently.
Lock files deliberately persist because removing a lock inode while another
process waits would let a third writer bypass it.

All requested files are prepared before replacing any existing output. Each
individual file is installed with an atomic replacement. If a later replacement
reports an error, already-replaced files are rolled back from retained previous
files. Failed compilation, validation, preparation, or handled publication
errors preserve the prior completed outputs. An already-correct module keeps its
modification timestamp on a cache hit. Source files, imported dependencies on
the direct path, and the compiler itself are protected against output collisions.

**Several file replacements are not a crash-atomic filesystem transaction.**
A SIGKILL, power failure, or machine crash between renames can leave different
generations of a JS/Wasm/stats set. The driver does not claim otherwise. An
unrelated reader of several files should validate the module digest from the
stats record or use its own generation-directory deployment scheme. Output locks
coordinate participating writers; they do not make unrelated readers atomic.
If an attempted rollback itself fails, the error identifies the saved previous
file rather than deleting the last recoverable copy.

## Statistics and measurement

A successful build reports:

- `compiler_mode`: `process`, `session`, or `cache`.
- `native_session_reused`, native process ID, and worker request number when a
  worker compiled the program.
- `full_frontend_ran` and `full_backend_ran`; these are true for edited builds.
- `compile_attempts`, `namespace_verified`, output size/digest, and cache status.
- Frontend and emitter phase counters, including parse, resolution, type check,
  optimization, bounds analysis, and direct emission.

Function names, module indices, code sizes, body hashes, and direct-call
relationships are also available. They describe generated output. An unchanged
body hash does not mean emission was skipped, and a transient module index is
not a persistent semantic identity.

The returned response includes publication in `total_ms` and reports
`publication_ms` separately. A `--stats` file is itself one of the prepared
outputs, so its `timing_scope` explicitly ends before publication. External
benchmark wall times include publication and response serialization.

The original 32-function chain can be measured with:

```sh
python3 bench/incremental.py --samples 15 --functions 32 \
  --output build/incremental-chain.json
```

For declaration-count scaling with flat independent callees:

```sh
python3 bench/incremental.py --samples 15 --sizes 32 512 2048 \
  --levels O0 O2 --output build/incremental-scaling.json
```

Both commands report six distinct costs: raw compiler process, uncached Python
wrapper, fresh-wrapper module-cache hit, unchanged persistent-server cache hit,
actual source edit using a fresh native process, and the same edit using the
resident native process. The two edit modes share the same source and use
separate caches; both must miss after every edit. Their order is shuffled within
each paired sample. Byte-for-byte comparison and execution with runtime input
validate **every edited artifact**, outside the measured build intervals.

The JSON report retains raw values, medians/MAD, source text, phase timings,
execution order, tool/source hashes, and per-edit validation. Markdown separates
the unchanged-cache result from actual edited-source latency. Large flat
workloads avoid mistaking a deep recursive dependency chain for a test of
ordinary declaration-count scaling. A source/compiler hash change during a run
invalidates the run.

## Remaining architectural work

The next substantive reuse boundary is semantic, not another whole-module cache.
Safe function reuse needs stable declaration/specialization identities, explicit
layout and inlining dependencies, and relocatable output for function/type/global
indices and data addresses. Retaining existing AST pointers after destroying a
compilation would be invalid; caching raw bytecode by function name would miss
surrounding index/layout changes. Those features are not implemented here.
