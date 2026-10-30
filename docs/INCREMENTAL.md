# Incremental compilation architecture

## Implemented now

The direct compiler consumes the existing typed/specialized Goose AST after the
normal optimization and bounds-analysis passes. It emits binary Wasm in memory,
without starting C compilation, a linker, or an assembler. This removes the
per-program C toolchain from the direct path.

The driver caches complete modules. A cache identity includes the native
compiler's SHA-256, the source path, optimization/debug flags, memory settings,
working directory, and relevant Goose environment, including the home-directory
fallback used to locate packages. The compiler returns the exact source and
`.build` configuration text it parsed, plus module-existence probes and absent
configuration paths. Cache records retain hashes of that content, lexical
import paths, their resolved targets, and module-search candidates. A hit
rechecks contents and negative observations, including when an editor preserves size and
timestamps. UTF-8 BOM handling matches the frontend. Retargeting a symlink or
adding a module that may shadow another import invalidates the entry.

The compiler records observations on its compilation thread. The driver
validates every observation against disk before retaining an artifact and
rejects conflicting repeated reads. This prevents accepting an artifact after
a configuration was read and then restored, or after a new local module
appeared after import selection. These checks cover recorded observations;
they do not provide a transactional filesystem snapshot. Builds that read
embedded files/shaders or perform a package-wide extern scan currently bypass
artifact storage, since those additional inputs are not fully traced. They
still compile normally. Configuration and probe paths, including absent ones,
are protected against output and statistics publication.

`--wasm-deps` and native-session responses use the same dependency transcript.
Source entries carry `path` and `text`; `kind: "build"` entries also carry
`exists`, `complete`, and the parsed `text` when readable; `kind: "probe"`
entries carry `path` and `exists`. Repeated observations are intentional. An
absent or false completeness marker disables artifact retention, including
when using a compiler built before this protocol extension.

A content-addressed Wasm blob is published before its cache record. Its digest
is verified on retrieval. A failed build never publishes a new executable, and
an unchanged hit does not touch an already-correct output file's timestamp.

`scripts/goose_wasm.py serve` retains the driver in a process and accepts
JSON-lines requests. It avoids Python process startup and memoizes tool hashes
against their filesystem identity. Artifact hits check source content on every
request. Its argument parser is constructed once and produces a fresh options
namespace for each request. It is a local build protocol, not a network service.

`serve --native-worker` also retains one native compiler process. The worker
uses a request API returning module bytes, exact parsed source dependencies,
diagnostics, and phase statistics. Its source provider accepts complete
per-request overlays for existing files, including imported files reached
through symlinks. An omitted overlay set means disk contents again. New files
must exist on disk for the frontend's import discovery to find them.

Each request owns and destroys a fresh mutable AST and its immutable source
snapshots. No AST objects or source views survive into the next build. The
checked caches described below retain pointer-free semantic values.
With the default worker, `parsed_files` counts every reached file and
`parsed_cache_hits` is zero. Python retains atomic artifact publication; overlay
builds bypass disk-only cache lookup and storage. Compiler-identity changes or
worker failure cause a new process to be started. Failed requests preserve the
previous output and do not poison the next request.

Overlay builds and `--no-cache` skip the additional disk-content and recursive
namespace checks used solely to qualify artifact retention. The compiler still
loads reached sources, and all returned source/configuration/probe paths remain
protected against output/statistics publication. Unchecked dependency snapshots
are marked incomplete and cannot validate as reusable cache entries.

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
`parsed_syntax_reused` records syntax reuse. With syntax reuse alone, resolution,
checking, specialization, optimization, bounds analysis, and emission still run
fully; `semantic_reused` and the legacy
`frontend_reused` flag remain false. Whole-
module artifact hits do not invoke the worker; their stored backend counters
describe the original compilation.

The syntax cache remains opt-in. The retained [O0/O2 comparison](../bench/results/2026-10-30/syntax-cache.md)
shows a smaller parse phase but no established end-to-end edited-build latency
improvement. It can be combined with the separate token cache below. The
storage estimates cover retained caches, rather than request ASTs or total
compiler memory.

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
the direct backend emits all reachable functions again. The optional checked
caches can skip individual body checks as described below. This
is not a general incremental type checker or a function emission cache.

## Checked scalar leaf reuse

`serve --native-worker --checked-leaf-cache` reuses successfully checked closed
scalar expression functions across requests. This is independent of parsed
module reuse and can be combined with both frontend caches. Eligible functions
have one explicit integer/float/bool result and fully typed scalar parameters.
Their bodies contain literals, parameter reads, arithmetic/boolean operations,
blocks, conditionals, and returns to themselves. Functions using calls, globals,
locals, loops, references/aggregates, captures, generic or literal parameters,
explicit casts, defaults, recursion, threads, or exports follow normal checking.
The preflight checks excluded constructs even in dead branches.

An exact key includes the filename, qualified name, declaration lines and
coordinates, resolved scalar signature, and concrete argument types. Positions
in the key conservatively invalidate shifted declarations. Scalar alias changes
invalidate their users even when the function text is unchanged. These closed
bodies have no external value dependencies or call edges.

Entries own strings, scalar type descriptors, node indices, parameter indices,
and source-origin ordinals. They retain no AST nodes or pointers. Import creates
fresh AST allocations, binds parameter owners and return targets to the current
specialization, and maps origins and locations to the current source index.
Float bits are preserved exactly. Implicit numeric casts retain their checked
target separately from their expression's result type. Optimizer and BCE facts
are not cached; both passes run on the fresh imported body.

Retention requires empty environment/effect/literal summaries, no cycle or
capture state, default scalar return-root summaries, and no store events.
Diagnostic or deferred cast-verdict changes refuse retention. Explicit source
casts are excluded because their warnings are decided after all roots check.
On import, store-event positions are rebased to the current checker's event
cursor. Caller overload resolution, argument fitting, signature checking, and
all other bodies continue through the normal checker.

The cache has a conservative 16 MiB storage estimate and 256-entry LRU bound.
Declarations larger than 64 KiB, syntax above 4,096 nodes or depth 128, and
oversized frozen entries bypass reuse. `checked_leaf_cache_hits` counts actual
body-check skips; misses, stored/refused entries, evictions, entry count, and
estimated retained bytes are reported separately. `semantic_reused` becomes
true when at least one checked leaf is imported. `frontend_reused` remains false.
An artifact hit reports the original build's stored statistics.

`tests/test_checked_leaf_cache.py` checks edits, alias changes, fresh module
equivalence, excluded bodies, source reindexing, errors, and storage bounds.
`tests/test_checked_leaf_ownership.py` destroys the producer AST before import
and evicts entries before optimizing/emitting the consumer under sanitizers.
The benchmark's `--shape leaves` workload keeps independent helpers unchanged
while editing their caller; its default `chain` workload remains available.
The retained [O0/O2 comparison](../bench/results/2026-10-30/checked-leaves.md)
demonstrates skipped body checks and smaller type-check phase medians, with
mixed edited-build wall times at O2. The mode remains opt-in.

## Checked scalar callers

`serve --native-worker --checked-scalar-cache` includes the leaf support and
adds checked callers with a deliberately narrow contract: bare canonical
`i64` parameters and result, one return or tail arithmetic expression, and
direct named calls with parameter identifiers as their positional arguments.
Arithmetic in these callers is limited to integer literals, parameter reads,
unary minus, addition, subtraction, and multiplication. Calls with computed or
literal arguments, conditionals in callers, short-circuiting, aliases or
qualifiers in their signatures, defaults, generics, UFCS, and other call forms
follow normal checking. Existing conditional/narrow/float leaf support remains
available in this mode.

A request-owned graph proof rechecks every selected function lookup and every
reachable current source body. Callees must resolve uniquely, have canonical
`i64` signatures, and form a closed acyclic graph. A caller parameter cannot
hide its unqualified callee name. Builtin names are excluded. Closure checks
also inspect dead branches of leaves. Overload additions, namespace shadows,
unsupported body edits, effects, and recursion cause conservative fallback.
Proof memoization lasts for one request, and is discarded when the declaration
table grows. It is bounded by 256 declarations, 4,096 syntax nodes, and 128
function levels; memoized graph heights enforce the depth limit too.

Each function keeps its own exact body key. Caller keys additionally include
the direct callee's filename, qualified name, declaration start, canonical
signature, and required attributes. A callee's body and end position are not
part of its caller's type-check contract. Thus changing `step0`'s literal in
the 32-function chain can recheck that body while reusing all 31 callers.
Shifting a declaration still conservatively invalidates position-based keys.

Restoration runs inside the normal checker's frame, after parameter and result
setup. The body importer preserves those fresh objects and the normal
epilogue. Calls are visited in source evaluation order, bind current
specializations through the normal specialization lookup/check path, enforce
`checkfree`, and require successful scalar return and empty-effect summaries.
Changed callee errors therefore retain the ordinary caller chain. Optimization
and BCE run again; inlining reads the edited callee's current body.

Frozen calls contain owned names/contracts and indices. The complete body and
contract strings are copied into request-owned storage before dependent checks
can evict cache entries. No `FnSpec*` is retained. The sanitizer harness covers
a capacity-one cache in which checking an edited callee evicts the caller
currently being restored, followed by cache clearing before optimization.

The storage pool retains the same 256-entry/16 MiB bound. This mode reports
`checked_scalar_cache_hits` with separate `checked_scalar_leaf_hits` and
`checked_scalar_caller_hits`, plus misses, stored/refused entries, evictions,
entry count, and estimated bytes. `semantic_reused` records any body reuse;
`frontend_reused` remains false. The narrower leaf option keeps its existing
counter names; selecting both options uses scalar mode.

`tests/test_checked_scalar_cache.py` compares warm and edited chains, diamonds,
argument order, namespaces, overloads, changed signatures, effects, recursion,
diagnostics, `checkfree`, source reindexing, and depth fallback against fresh
compilation. The ownership harness now covers leaf and caller import, nested
eviction, cold and memoized depth limits, and O0/O2/debug/source-index variants.
The retained [32-function chain comparison](../bench/results/2026-10-30/checked-callers.md)
demonstrates reuse of all 31 callers after a `step0` edit, with no established
end-to-end latency improvement. Validation and import remain part of the cost.

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
5. A single-function source edit through the server, rechecking callers and emitting again.

It preserves raw timings, phase medians, function-hash changes, and a verified
result for the final edited program. The Python wrapper may cost more than a
very small raw compilation; the report keeps that overhead visible.

The [native-session comparison](../bench/results/2026-10-30/native-session.md)
records repeated local measurements with and without `--native-worker`,
including scheduling noise and first-request costs.
Pass `--native-worker --lexical-cache` to the benchmark to measure token reuse
separately from native process retention, or `--native-worker --syntax-cache`
to measure parsed-module reuse.
Use `--optimization O0`, `O1`, or `O2` to compare edit and release settings;
the default is O0.
Use `--edit-source-mode overlay` with a native worker to time unsaved edits;
the default writes edits to disk and measures artifact-cache validation too.
`--driver PATH` selects a driver revision for controlled comparisons. Reports
separate server round-trip, driver build, and native request medians, retaining
the expected and actual final output in both edit modes.
The [driver comparison](../bench/results/2026-10-30/driver-overhead.md) records
lower local request medians after parser reuse and removal of artifact checks
for unsaved overlays, with the same compiler and semantic-cache settings.

## Next architectural steps

**Persistent semantic state.** The session, syntax importer, checked scalar
leaves and restricted callers establish ownership and contract dependencies
for narrow reusable semantic results. General
functions need explicit dependency versions and summaries for calls, globals,
lifetimes, and environments. Existing Goose clones
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
