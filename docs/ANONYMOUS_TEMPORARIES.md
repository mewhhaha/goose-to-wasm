# Completing fixed-element growable temporaries

This follows the Astra xhigh review of the pinned frontend and native allocation
scopes. The scope foundation prepares named receivers before initializer
watermarks and scopes statements, tails, match arms, short-circuit right operands,
while conditions and fixed-array default iterations. The single-result
materializers and argument lifetimes below are now implemented, including
discarded mixed/multiple-result ordinary calls. Function-value ownership remains gated.

`CheckBranchRoot` rejects references/slices into temporaries created inside a
departing block. An owned construct's result instead needs a receiving temporary
allocated **before** entering its body. This permits emission-time allocation;
do not reserve regions by walking the whole statement in advance. `MayMaterialize`
only decides whether to save a watermark and allocates no region.

## Materialization

- Require the current `TempScope` to own a restoring watermark. Fail closed when
  a scope without one changes `region_live`.
- Allocate a fresh header/region for a natural owned result, increment a monotonic
  materialization serial, construct into it and adapt its view afterward.
- Initial producers are single-result direct calls/inline blocks, owned
  array/string literals, supported copies and owned control expressions.
- Ordinary calls allocate missing result channels after evaluating value arguments,
  before passing the hidden destination arguments. This also covers discarded
  multiple results and permits recursion in argument evaluation. Explicit receiving
  channels retain their existing allocation point. Inline result allocation precedes
  its argument prelude, matching the pinned native emitter and named-result binding.
- Determine call results from the specialization's natural results, including
  when the expression has already adapted to a slice. Existing identifiers,
  fields, indices and reference values remain locations.
- A supplied destination suppresses materialization. Recurse through `copy` when
  constructing into a destination, so a fresh producer can receive it directly.
- Do not cache materialized values by AST node: default/function-value bodies can
  emit the same node in separate evaluation occurrences.

Temporary private headers should record their actual temporary-scope lifetime,
not the depth of an incidental argument-group cleanup. Add a temporary tag to
the header registry for the inline-argument filtering below. Keep unsupported
function-value ownership and variable elements refused.

## Argument lifetimes

Ordinary owned arguments retain their safe short call scope when the anonymous
serial is unchanged. If arguments materialize an anonymous owner, drop only the
argument group's cleanup action, without restoring its watermark or compile-time
`region_live`; the enclosing temporary scope now releases the retained regions.
Assert that nested scopes have closed before dropping that action. Allocations
inside branches that already closed may cause conservative retention.

Inline argument declarations must execute before the inline body's cleanup scope:

1. Bind named results, including eligible inline parameter declarations.
2. Open an argument group and install the inline exit.
3. Prepare/initialize the `inline_arg` prefix without per-declaration initializer
   scopes. Owned parameter headers have a logical lifetime inside the inline exit,
   even if their data is retained until the enclosing statement ends.
4. Emit `BlockInto` while skipping that prefix.
5. At the common exit release or retain the group using the serial. Remove private
   parameter registrations, preserving anonymous argument headers owned by the
   enclosing temporary scope. Remove this inline body's named-result mappings.

The receiver of an owned inline result is acquired before its argument group.
Scalar-returning inline calls can still acquire owned parameter regions from plain
identifier arguments; their balanced group must handle that predicate edge.

## Scope checks

A temporary `for` sequence lives through the loop. Each `while` condition instead
captures its bool before closing its scope, with the loop exit already installed
so condition break/continue unwind correctly. Match arms and evaluated logical
right operands capture their result before closing. Each generated default-array
iteration releases its own temporaries.

Acceptance covers immediate length/index/printing, discarded copies, borrowed
results consumed later in a statement, mixed owned/borrowed arguments, owned
construct results used outside their blocks, repeated conditions/defaults,
temporary sequences, interrupted arguments, and recursion after a completed
temporary statement. Keep native frontend rejection checks for escaping inner
temporaries. Recursive SCC accounting must keep real live-region offsets; never
suppress its failures to accommodate a scope mismatch.
