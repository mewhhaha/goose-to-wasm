# Next development milestones

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
