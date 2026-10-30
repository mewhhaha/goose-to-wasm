# Incremental compilation architecture

## Implemented now

The direct compiler consumes the existing typed/specialized Goose AST after the
normal optimization and bounds-analysis passes. It emits binary Wasm in memory,
without starting C compilation, a linker, or an assembler. This removes the
per-program C toolchain from the direct path.

The driver caches complete modules. A cache identity includes the native
compiler's SHA-256, the source path, optimization/debug flags, memory settings,
working directory, and relevant Goose environment. The compiler returns the
exact source text it parsed, including imports. Cache records retain hashes of
that content, lexical import paths, their resolved targets, and module-search
candidates. A hit rechecks contents, including when an editor preserves size and
timestamps. UTF-8 BOM handling matches the frontend. Retargeting a symlink or
adding a module that may shadow another import invalidates the entry.

A content-addressed Wasm blob is published before its cache record. Its digest
is verified on retrieval. A failed build never publishes a new executable, and
an unchanged hit does not touch an already-correct output file's timestamp.

`scripts/goose_wasm.py serve` retains the driver in a process and accepts
JSON-lines requests. It avoids Python process startup and memoizes tool hashes
against their filesystem identity. Source content is still checked on every
request. It is a local build protocol, not a network service.

`serve --native-worker` also retains one native compiler process. The worker
uses a request API returning module bytes, exact parsed source dependencies,
diagnostics, and phase statistics. Its source provider accepts complete
per-request overlays for existing files, including imported files reached
through symlinks. An omitted overlay set means disk contents again. New files
must exist on disk for the frontend's import discovery to find them.

Each request owns and destroys a fresh mutable AST and its immutable source
snapshots. No resolved types or checked nodes survive into the next build.
`frontend_reused` is false, `parsed_files` counts every reached file, and
`parsed_cache_hits` is zero. This is native session infrastructure, not parsed
syntax or semantic reuse. Python retains atomic artifact publication; overlay
builds bypass disk-only cache lookup and storage. Compiler-identity changes or
worker failure cause a new process to be started. Failed requests preserve the
previous output and do not poison the next request.

## What an edit currently costs

Any semantic source change misses the whole-module cache. The existing frontend
then reparses, resolves, checks, specializes, optimizes, and analyzes the program;
the direct backend emits all reachable functions again. This is **not yet an
incremental type checker or a function compilation cache**.

Compiler statistics expose time spent in parsing, resolution, type checking,
optimization, bounds analysis, and direct emission. Each emitted function also
has a name, current module index, body byte count, deterministic bytecode hash,
and direct call dependencies. These fingerprints are useful for understanding
how much generated code an edit changes. They do not imply that generation was
skipped, and module indices are not a persistent symbol identity.

`bench/incremental.py` reports five distinct costs:

1. A fresh raw native-compiler invocation.
2. An uncached Python-driver invocation.
3. A fresh driver process hitting its dependency-checked module cache.
4. An unchanged request through the persistent server.
5. A single-function source edit through the server, with full frontend/emission.

It preserves raw timings, phase medians, function-hash changes, and a verified
result for the final edited program. The Python wrapper may cost more than a
very small raw compilation; the report keeps that overhead visible.

The [native-session comparison](../bench/results/2026-10-30/native-session.md)
records repeated local measurements with and without `--native-worker`,
including scheduling noise and first-request costs.

## Next architectural steps

**Persistent frontend state.** Introduce a compiler session owning source
snapshots and dependency nodes. Goose's existing source-provider interface can
supply edited buffers without requiring changes to the language parser. AST and
type lifetimes must be explicit before nodes can survive across requests.

The native worker now supplies the request/source ownership boundary. The next
step is an immutable parsed-module representation and a complete syntax-import
cloner. Existing Goose clones share declaration symbols and parsed types that
resolution/checking mutate, so they cannot safely be reused as this cache.
The cloner must remap types, declaration ownership, source strings/indices,
namespaces, defaults, and nested declarations into a fresh compilation AST.
Import resolution and global initialization order must be recomputed. A first
syntax-cache milestone should prove one reparsed module after a one-module
edit, while resolution, checking, optimization and emission still run fully.

**Stable semantic keys.** Function identities should be based on declaration,
specialization arguments, relevant type/layout facts, captures, and target
options, not transient AST addresses or module indices. Inlining creates
dependencies on callee bodies as well as signatures; global layout, literals,
and imports can also invalidate otherwise unchanged function code.

**Relocatable function output.** Cache symbolic function bodies with fixups for
calls, type indices, globals, data addresses, and host imports. Lay out/link the
module separately. A raw bytecode hash is insufficient to safely reuse a body
when the surrounding indices or layouts change.

**Dependency-based invalidation.** First reuse exact typed/lowered inputs and
their explicit dependency versions. Then narrow invalidation of type checking,
specialization, optimization, and bounds facts. Preserve the C oracle as an
independent check after each stage.

**Measure before adding complexity.** Use the phase counters to identify the
dominant cost for real workloads. Keep O0 fast-edit builds and O2 release builds
separate, and measure both first-build and edited-build latency. Correct
invalidation is part of the compiler's semantic contract.
