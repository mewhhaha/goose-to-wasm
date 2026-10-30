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
With the default worker, `parsed_files` counts every reached file and
`parsed_cache_hits` is zero. Python retains atomic artifact publication; overlay
builds bypass disk-only cache lookup and storage. Compiler-identity changes or
worker failure cause a new process to be started. Failed requests preserve the
previous output and do not poison the next request.

`serve --native-worker --syntax-cache` retains pristine parsed modules. Each
entry owns its source, AST, raw import records, and structured parse warnings;
it is never resolved, checked, optimized, or emitted. A dedicated importer
copies live syntax into the new request AST, remapping declarations, types,
shared type details, defaults, nested functions, names, and source indices.
Canonical primitives belong to the request, and source-backed views are
rebased into its source buffers. No origin or semantic pointer refers to the
cached AST. Abandoned parser allocations are not traversed, since they can
contain edges to types or declarations that backtracking already deleted.

The cache checks exact filename, complete parsed source bytes, and fetched
package status, which controls deprecated-syntax warnings. It retains at most
128 entries within a conservative 64 MiB storage estimate, evicting the least
recently used entry first. Oversized entries compile without retention. A failed isolated
parse, or a type/global name collision with preceding modules, runs the original
parser in the request AST to preserve diagnostics and recovery. Successful
imports replay warnings with the current source index. Imported `main`
registration follows the current root role. Package discovery, import target
resolution, source ordering, and global initialization ordering run afresh.

On compiled requests, `parsed_files` counts files actually parsed and
`parsed_cache_hits` counts reused templates. An unchanged request forced through
the compiler can parse zero files; editing one helper can parse just that file.
`parsed_syntax_reused` records syntax reuse. Resolution, checking,
specialization, optimization, bounds analysis, and emission still run fully;
`semantic_reused` and the legacy `frontend_reused` flag remain false. Whole-
module artifact hits do not invoke the worker; their stored backend counters
describe the original compilation.

The syntax cache is opt-in pending latency measurements. It can be combined
with the separate token cache below. The storage estimates cover retained
caches, rather than request ASTs or total compiler memory.

`serve --native-worker --lexical-cache` additionally retains scanner
transitions for unchanged files. Exact filename and complete parsed source bytes
(after normal UTF-8 BOM removal)
identify a snapshot; timestamps and source addresses are not cache keys.
Transitions contain source offsets, token values, and guards for the incoming
line, line-start position, and brace depth. Replaying them rebases every source
view into the new request's source allocation. Failed scans are never cached,
so lexical errors and parser recovery follow the normal scanner path.

The cache uses a 32 MiB retained-storage estimate and at most 256 files, with
least-recently-used eviction. Lexer copies pin live entries. Oversized sources
or exhausted budgets fall back to scanning. String tokens retain only their
own decoded payload, rather than copying a previous string into later tokens.
This limit covers retained cache storage; it is not a limit on AST or total
compiler memory.

`lexical_reused_tokens` counts transitions created by an earlier request;
`lexical_lookahead_hits` counts reuse within the current request.
`scanned_source_files` counts lexer input files requiring real scanning, and
`lexical_reused_files` counts files with transitions reused across requests.
These can include package build/configuration files beyond the AST's Goose
source files.
A file may contribute to both when only some transitions are retained.
Used without the syntax cache, changing one module can reuse unchanged imports'
tokens, but all files are still parsed and checked: `parsed_cache_hits` remains zero and
`frontend_reused` remains false. The mode remains opt-in: the retained
[comparison](../bench/results/2026-10-30/lexical-cache.md) demonstrates token
reuse but does not establish an edited-build latency improvement.

## What an edit currently costs

Any semantic source change misses the whole-module cache. The existing frontend
then parses changed files (or every file without the syntax cache), constructs
a fresh AST, resolves, checks, specializes, optimizes, and analyzes the program;
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
5. A single-function source edit through the server, with full semantic analysis/emission.

It preserves raw timings, phase medians, function-hash changes, and a verified
result for the final edited program. The Python wrapper may cost more than a
very small raw compilation; the report keeps that overhead visible.

The [native-session comparison](../bench/results/2026-10-30/native-session.md)
records repeated local measurements with and without `--native-worker`,
including scheduling noise and first-request costs.
Pass `--native-worker --lexical-cache` to the benchmark to measure token reuse
separately from native process retention, or `--native-worker --syntax-cache`
to measure parsed-module reuse.

## Next architectural steps

**Persistent semantic state.** The session and pristine syntax cache now
establish source and declaration ownership. The next boundary is reusable
semantic results with explicit dependency versions. Existing Goose clones
share declaration symbols and mutable types, so checked ASTs cannot simply be
retained across requests. Measure the cost of syntax import and repeated
resolution/checking before choosing their replacement representations.

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
