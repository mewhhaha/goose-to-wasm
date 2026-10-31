# Runtime case-function dispatch

The frontend resolves a complete ordered arm set and one enum argument position.
The direct backend uses those checked specializations; it does not select
overloads or fill defaults again. The admitted cases use existing fixed layouts,
nonresizable variable enum payloads and supported owned parameter/result layouts.
The pinned frontend rejects dispatch on resizable enum payloads.

Arguments evaluate once, left to right, before choosing a case. Scalars,
references and slices are saved immediately. Fixed aggregate arguments receive
value snapshots, while owned arguments receive independent regions at their
argument position. The enum argument has separate rules:

- Fixed-mode enums snapshot the complete fixed value and tag.
- Variable-mode enums retain the original image for reference arms.
- A variable-size by-value payload requires one deep enum snapshot before later
  arguments execute; the selected case receives its private payload control.
- When every by-value payload is fixed, only those fixed payloads are copied.
  These snapshots use activation storage, with no extra data region across a
  recursive reference case. Empty values receive initialized placeholders.

Each selected call receives the saved shared arguments, its payload value or
address, its own mapped capture addresses and common result destinations.
Capture analysis propagates the union of case requirements to the caller while
keeping each case's signature independent. All return channels are prepared
after the arguments and published once after the switch. An invalid host-written
tag aborts before any case executes.

Dispatch calls normal case functions, including when its result feeds append.
It does not select a variable-array element-run twin: a case returning `u8[u8]`
still checks 256 elements and fails. Different receiving length widths adapt
after the natural result. Recursive calls preserve the frontend's exact-type
forwarding rule; receiving a wider result outside the recursive cycle is covered.

Five fixtures are unchanged copies from pinned revision
`2e2bedef5b980bf013cac5aaa0095bfea64e5569`:

- `test/codegen/dispatch_evaluation_order.goose`
- `test/lifetimes/dispatch_copied_reference.goose`
- `test/codegen/dispatch_resizable.goose`
- `test/typing/nested_overloads.goose`
- `test/typing/dispatch_result_no_reference.goose`

Their local names add `upstream_`. Additional fixtures cover recursive references,
natural narrow results, captured case functions after parent inlining, shared
reference argument spilling and wider receivers outside recursive cycles.
Resource checks exercise repeated owned results and deep payload copies; malformed
tag tests mutate exported memory and verify both engines abort without changing
the neighboring owner. Out-of-line nonlocal effects and unsupported layouts keep
their existing diagnostics.
