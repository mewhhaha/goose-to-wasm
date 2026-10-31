# Next development milestones

The ordered [completion plan](IMPLEMENTATION_PLAN.md) covers the remaining
runtime, language, incremental-compilation and qualification work, including
ownership contracts and acceptance gates. Completed slices are recorded below.

## Implemented: static captured environments and owned callbacks

Hidden addresses carry current-activation bindings through ordinary, recursive
and transitive nested calls, including mutable reference/slice bindings and
supported owners. Callback-owned parameters and single results use independent
storage, natural result contracts, argument snapshots and scoped cleanup.
Exact result forwarding preserves recursive region bounds; a callback tail is
a value copy. See [static captures](STATIC_CAPTURES.md) and
[owned function values](OWNED_FUNCTION_VALUES.md). Borrowed callback-local
results remain conservatively gated. Fixed nonlocal effects are described below.

## Implemented: fixed and growable/frame nonlocal result groups

Activation mailboxes propagate fixed/scalar/mixed fixed returns through ordinary
and dispatched calls, preserving the innermost concrete target across recursion.
Live-owner records distinguish dying headers from surviving storage during
interrupted reconstruction, including embedded enum tails and private parameters.
Logical temporary lifetimes survive early inline returns and retained arguments.
The original function-value capture program now qualifies at O0 as well as O2.
A [single growable-array or frame target](NONLOCAL_RETURNS.md) now stages behind existing
data and lands at its catch without acquiring another data region. Physical
cursors preserve canceled partial data, while receiving controls publish lengths
and frame fields during interrupted construction. Owned results may appear beside fixed results at any ordinal. All receiving
cursors snapshot before source evaluation; independent controls commit and land
together. Unsupported owned image kinds remain pending. Frame catch snapshots preserve nested fixed prefixes and adjust the
winning tail base relative to the copied suffix; canceled attempts retain tail
bytes while discarding their private prefix.

## Implemented: unsigned array value images

Var values store unsigned length prefixes in their data region; runtime-limited
values store capacity and length before their reserved slots. Physical modes
separate those values from raw element-run channels, with authoritative views,
full-capacity copies, normal return staging and control-only prefix adapters.
The [array-image contract](ARRAY_IMAGES.md) records call ordering and receiving
anchors. Actual image-valued nonlocal targets and general record/enum images
remain subsequent work.

## Implemented: runtime enum case dispatch

Case calls evaluate shared arguments once, snapshot value payloads before later
arguments, and retain original storage for reference payloads. Case-specific
captured addresses and common result destinations feed ordinary emitted calls.
Fixed payload snapshots consume no data region, preserving recursive reference
visitors. Variable-array result arms keep their natural width checks even in
append. See [the dispatch contract](FUNCTION_DISPATCH.md).

## Implemented: packed fixed record fields

Layout version 3 packs fixed struct and variant fields, including nested records,
generic instantiations and their array strides. Enums whose payloads recursively
contain fixed-width integers, nonempty fixed arrays and nonempty fixed records
reproduce native overwrite observations through saved named-payload references.
Owner controls retain their separate alignment. Empty embedded aggregates and
other representation-sensitive cases retain explicit boundaries. The
[image layout plan](IMAGE_LAYOUT.md) separates this step from compact metadata
and authoritative variable images.

## Implemented: standalone variable-size variants

Supported `E.Variant` payloads share the single-tail record walker with structs:
independent owned copies/parameters, prefix references, nested tails, recursive
and mixed results, control construction and whole-record named aliasing. Each
variant is validated independently of its siblings. See [the variant contract](VARIABLE_VARIANTS.md).
Resizable variants and nonfixed payloads inside `E..` still need later lowering.

## Implemented: nonresizable variable-mode enums

`E..` owns a stable region image without entering the fixed-copy path. Ordinary,
inline and recursive calls, parameters, mixed results, named aliasing, fixed mode
conversions and copied/borrowed payload matches share the ownership channels.
Active payload copies, direct variant-result routing and tag-aware interrupted
construction support single-tail variable payloads. The [enum contract](VARIABLE_ENUMS.md)
records control-union resource costs and remaining resizable payload, containing
owner and packed-overlap boundaries.

## Implemented: growable frame structs and nested single-tail owners

Frame objects snapshot every prefix and the tail length at each named return,
while sharing stable tail elements. Whole reconstruction pins the receiver and
writes fields in declaration order, preserving later fields on an early exit.
Final owner fields may nest through two or more fixed prefixes to a single
terminal array; allocation and cleanup reach its one ultimate header. The
[struct contract](VARIABLE_STRUCTS.md) describes both variable and frame rules.

## Implemented: fixed-prefix structs with one variable/capacity-limited tail

Standalone variable structs use a fixed control layout with one embedded array
header and a separately owned tail region. Constructors walk checked fields in
declaration order; copies preserve fixed prefix values and independently construct
tail data. Named results alias the whole receiving object, including prefix and
tail-header mutations by later result expressions. Generic types, checked global
defaults, borrowed prefix/element references, by-value calls, control results,
interrupted construction and limited field assignment share this path.
This original slice covered immediate array tails. Nested final owners and
growable-tail frame objects are described above; multiple variable fields remain
pending. The reviewed [struct design](VARIABLE_STRUCTS.md) records the boundary.

## Implemented: unsigned variable-array lengths and element-run calls

`T[u8]`, `T[u16]` and `T[u64]` join default/u32 variable arrays. Natural value
construction checks the declared width; element-run calls propagate raw counts
to growable or differently prefixed receivers, which check their own width.
Owned parameters and local declarations retain their width requirements.
Mixed results preserve natural checks, while inline construction follows its
receiving request. The oracle matrix records the pinned optimizer's differing
normal/inline outcomes. Varint images remain pending.

## Implemented: fixed-element runtime-capacity arrays

Runtime `T[..]` owners now use the uniform internal region control with
separate logical capacity and resource limit. Copies preserve spare capacity;
cross-kind construction chooses capacity from length. Assignment constructs its
RHS before updating the pinned receiver and preserves capacity, including self
reads and interrupted RHS evaluation. Natural result channels preserve limited
array semantics during ordinary/inline, mixed, forwarded and named-result calls.
Capacity-literal effects and range checks survive optimized conversions.
Variable elements and containing values remain pending.

## Implemented: fixed-element variable arrays with default/u32 lengths

`T[]` and `T[u32]` now use stable regions for construction, independent by-value
parameters, owned results and scoped temporaries. Views, element writes, loops
and primitive rendering use their frozen length. Growable locals selected by the
native named-result analysis share data with variable-array results, including
mutations by later result expressions. Varint lengths, variable elements
and containing values remain pending. The reviewed
[variable-array plan](VARIABLE_ARRAYS.md) separates these from runtime capacity
and its distinct copy/assignment behavior.

## Implemented: single owned growable temporaries

Single-result growable calls, inline results, supported copies/literals and owned
control expressions now materialize into their current temporary scope. This
supports immediate len/indexing/rendering, append sources, sliced construct
results, temporary loop sequences and default expressions. Each evaluation gets
its own destination; repeated use of one AST does not reuse an earlier value.

Arguments retain anonymous owners through their enclosing scope when a borrowed
result can still refer to them. Inline argument declarations run before body
cleanup, with parameter headers distinguished from retained temporary headers.
Ordinary owned-only argument groups keep their shorter safe release when no
anonymous owner was materialized.

Qualification covers nested inline/mixed arguments followed by allocations,
iteration/condition/default cleanup, constructor receiver preservation,
interrupted arguments and recursion after a completed temporary statement.
Discarded mixed/multiple-result calls acquire each owned result after evaluating
their arguments. Recursive argument calls therefore retain no premature result
region. Function-value ownership remains an explicit boundary. The frontend
rejects views escaping their temporary scope.

## Implemented: temporary scope foundation and condition exits

Named declaration receivers are prepared before their initializer watermark.
Statements, tails, match arms, logical right operands, while conditions and
generated default-array iterations now have explicit temporary scopes. Their
watermarks preserve named owners and restore runtime and compile-time region
state together; a scope without a watermark must leave the region count unchanged.

While exits are installed before their condition is emitted. Break/continue in an
ordinary condition block therefore select that while loop, including inside an
outer loop. The new C-oracle regression also exercises condition-local owners.

The reviewed [materialization design](ANONYMOUS_TEMPORARIES.md) records their
allocation sites, inline argument preludes and borrowed argument lifetimes.

## Implemented: fixed and slice results into owned receivers

Forwarded multi-result calls preserve each producer's natural ABI type, capture
all results once and then adapt them in order. Fixed arrays, slices and references
to them copy into supplied growable regions. Existing owned-result channels stay
direct. Copies observe the completed call, including later result expressions
that mutate an earlier slice's source or rebind its referenced slice slot.

Tests cover mixed fixed/slice/grow/shrink/reference results, fixed elements holding
external references, repeated calls and exact receiving-region counts. Runtime
limited-capacity literals remain refused after inlining, preserving their pending
status rather than dropping capacity-expression effects.

## Implemented: whole growable-owner assignment

Assignment pins the destination header before evaluating its RHS, keeps its data
region and reconstructs in place. The frontend rejects RHS access to the owner
being rebuilt, including through calls. Copies, fixed producers, conditional
values, reference targets, mutable owned parameters and repeated replacement are
qualified.

Length publication follows the producer: literals publish before element/fill
effects; a call or control expression waits for its selected producer. Interrupted
construction checks a surviving header's advertised extent before continuing.
Private headers that die at that exit need no reservation, including owned
parameters and named-result locals whose data region survives elsewhere.

Tests compare those interruption states with the C oracle, preserve neighboring
region canaries after oversized advertised lengths, and exercise aliases,
reference retargeting, surviving loop owners and repeated scope cleanup.

## Implemented: owned construction through control flow

Conditionals, ordinary/early blocks, value-producing loops and integer/bool/fixed
enum matches construct growable results into their receiving region. A `break`
constructs its value before releasing the scopes it leaves; loop iterations
release their local owners while preserving the receiver. Divergent match arms
use their enclosing return destination, and scrutinees are evaluated once.

Tests cover nested loop/match/block cleanup under a small memory budget, payload
bindings, local-owner copies, early returns and repeated exported calls. General
anonymous temporaries remain subsequent work.

## Implemented: multiple owned results and named-result construction

Each result position has its own destination channel. Calls can return growable
owners alongside scalars and fixed values; multi-name receivers acquire their
owned regions before the call. Forwarding passes those channels through recursive
cycles without acquiring more result regions. Fixed result storage keeps its
existing ABI.

The pinned `NamedResultOf` analysis chooses eligible locals on the final body.
A named local shares its receiving region from declaration onward, with its own
length header. Its result publishes that length at the corresponding return
position. Later result expressions may change the shared elements or grow the
local; they do not change the earlier result's published length. Other returned
positions copy as required. Tests cover these effects and rejected candidates.

Anonymous multiple-result calls remain an explicit boundary.

## Implemented: owned growable parameters

Ordinary calls construct each by-value growable parameter into a private region
in argument order. Those regions remain live through the call and are released
after its results, including when argument construction exits early. Callees use
the supplied header directly; inline parameter declarations use their enclosing
inline scope. Named nonfixed arguments still require the language's explicit
`copy` when passed by value.

Qualification covers copy independence, later-argument mutation, literals,
fixed/limited sources, owned-result arguments, grow/shrink operations, returned
owners and fixed results, and valid surviving external references in elements.
The frontend rejects escaping references/slices into the parameter's own storage.
Static function-value parameters are covered by the callback slice above.
Anonymous reference/view shapes outside the admitted temporary scopes remain boundaries.

## Implemented: single owned growable results

A function returning one fixed-element growable value receives the caller's
destination header. Named local/global receivers acquire a region before the
call; the callee constructs into it before releasing its own locals. Forwarding
calls, including recursive cycles, reuse that destination without acquiring
another result region. Inline bodies carry the same destination on their return
target, so nested returns select the correct owner.

Literals, local owners, fixed/limited results, slices and conditional results
are qualified at O0/O2. Anonymous owner temporaries remain explicit boundaries.

## Implemented: stable regions for named growable owners

Named local/global `T[>..]` and `T[>..<]` values with supported fixed-layout
elements now use stable data regions. Owner references point to frame/static
headers; element references and slices remain valid across growth. Construction
supports literals/fills, implicit empty globals, copies, slices and natural fixed
results, including optimized inline producers. Borrowed reference parameters and
results, shared mutation paths, primitive rendering and scope cleanup work at
O0/O2.

The static planner counts globals separately and bounds live transient owners
through the call graph and recursive components. Runtime acquisition/growth,
activation frames and print scratch all check their own limits. Module metadata
and compiler statistics publish the resulting partition budgets.

General result/temporary destinations,
variable elements and dynamic containing structs remain explicit
boundaries. Single owned results now use the receiving-region ABI above.

## Implemented: typed storage and cleanup boundary

Locations describe the actual variable/field/element storage separately from
the expression type. Fixed-value capture/copy/publication now share one checked
path, including arguments, results, aggregate pop, supported print snapshots and
parameter spills. Fresh destinations cover literals, adaptations and owned call
results. Assignment pins its destination before evaluating the complete RHS.

An explicit cleanup stack records each exit target's cleanup depth. Normal
completion and return/break/continue restore the scratch scopes they leave;
an inner loop keeps its enclosing print's captured arguments alive. Ordinary
reference/slice copies still preserve aliases. Physical size-class checks stop
nonfixed owner descriptors from entering fixed aggregate copies.

This preserves the fixed-frame ABI and supplies the boundary used by stable data
regions and the single owned-result destination ABI. General dynamic result
destinations remain subsequent work.

## Implemented: static-capacity limited arrays

`T[..k]` now uses a runtime length and stable inline storage within the existing
fixed-value ABI. Shared views feed indexing, slicing, iteration and rendering.
Construction, copying, parameters and owned results retain fixed-value semantics;
len/cap/index_of and push/append/pop/pop_n/resize/clear use checked mutation paths.
Loops capture calls and indices once and reload the current sequence location,
including nested array/slice slots replaced during iteration.

Qualification includes boundary failures, nested values, reference elements,
retained references through refill, overlapping append, receiver rebinding,
argument-side mutation, copies and recursive/multiple results at O0/O2 and debug.
Construction-time capacity remains subsequent work; named fixed-element
growables use the stable-region runtime described above.

## Implemented: fixed-mode enums and payload matches

The fixed-value backend now supports fixed `TY_ENUM` and `TY_VARIANT`
values: constructors, fieldless constants, local/global/fixed-array storage,
function parameters and owned results, and matches with copied payload bindings.
Variable-mode `E..`, dynamic dispatch, enum rendering/comparison, and aggregate
host imports/exports remain outside this milestone.

The implementation:

1. Defines a target-specific tag and aligned payload layout. It caches each variant's
   layout independently of the full enum, so sibling-variant fields do not
   introduce artificial layout recursion.
2. Extends aggregate classification, construction, field access, and
   variant-to-enum conversion. A payload needs a newly initialized tag and
   destination; its address alone does not represent an enum.
3. Extends matches using the frontend's resolved variant and binder metadata.
   It evaluates the scrutinee once and copies the selected payload before executing
   the arm. References to fixed enums still produce by-value payload bindings.
4. Reuses the existing caller-owned aggregate-return storage and snapshots.
   It respects concrete function result types when an optimized call or inline
   block has already been adapted to an enum expression type.

Qualification uses O0/O2 differential checks across native, C-Wasm, V8 and
Wasmtime for empty and differently aligned payloads, generic and nested enums,
variant replacement, arrays, defaults, reference scrutinees, copy independence,
recursive/mixed returns, and argument/result evaluation order. Excluded forms
have explicit refusal tests. The frontend already rejects by-reference
bindings into fixed-mode enum payloads.

## Incremental frontend reuse

Implemented foundation: an opt-in persistent native worker, request-owned
source overlays, and a fresh AST per request. Optional bounded caches reuse
scanner transitions or pristine parsed modules for unchanged files. Syntax
imports remap declaration/type/source ownership into the request, while import
resolution and all semantic analysis still run afresh. A one-module edit can
now reparse one module. The next boundary is semantic reuse with explicit
dependencies, as described in [the architecture](INCREMENTAL.md).

The [retained O0/O2 measurements](../bench/results/2026-10-30/syntax-cache.md)
complete this syntax-reuse slice: parsing is reduced, while edited-build
wall time has no established improvement. Both frontend caches remain opt-in.
Artifact reuse additionally validates configuration reads and module-search
probes; untracked embedded inputs and package-wide scans bypass storage.

The next implemented semantic slice is opt-in reuse of checked closed scalar
leaf functions. Exact declaration/resolved-signature keys and pointer-free
frozen bodies allow unchanged eligible functions to skip body checking in a
fresh AST. Callers, excluded functions, optimization, bounds analysis, and
emission still run normally. Calls, globals, captures, references, and general
specializations require subsequent dependency and environment contracts.

Restricted scalar callers now revalidate closed callee contracts and bind
current specializations. Editing the bottom of a 32-function canonical-i64
chain can recheck one body and reuse 31 callers. This remains bounded to direct,
uniquely resolved, acyclic calls and parameter-only arguments; general calls,
lifetimes, globals, and generic specialization are subsequent work.

Continue measuring parsing, specialization/type checking, optimization, bounds
analysis, and emission separately. The retained 32-function experiment spends
about 4.7 ms in parsing/type checking and 0.086 ms in direct emission, so a raw
function-body cache would address little of that workload's edited-build cost.

Persistent semantic state needs explicit AST/type lifetimes, source snapshots,
stable specialization identities, and dependency-based invalidation. Reusable
function output also needs relocations for calls, globals, literals and types;
the current bytecode hashes are measurements rather than safe cache keys. See
[the incremental architecture](INCREMENTAL.md).

Growable arrays remain a separate runtime milestone requiring allocation,
growth, lifetime, aliasing, and return contracts.
