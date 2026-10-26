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

## Next architectural steps

**Persistent frontend state.** Introduce a compiler session owning source
snapshots and dependency nodes. Goose's existing source-provider interface can
supply edited buffers without requiring changes to the language parser. AST and
type lifetimes must be explicit before nodes can survive across requests.

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
