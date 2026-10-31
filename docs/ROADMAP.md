# Next development milestones

The ordered [completion plan](IMPLEMENTATION_PLAN.md) covers the remaining
runtime, language, incremental-compilation and qualification work, including
ownership contracts and acceptance gates. Its first implementation slice is
static-capacity resizable arrays.

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
Construction-time capacity and growable arrays still need the location,
construction-destination and stable-region runtime phases in the completion plan.

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
