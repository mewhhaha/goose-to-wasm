# Sequential varint array elements

Internal layout 11 admits standalone immutable `varint[u8/u16/u32/u64]` arrays
and whole `varint[:]` views. Metadata keeps the existing unsigned fixed width;
elements are packed signed zigzag ULEB128 images with no fixed stride. The aligned
24-byte owner controls, scalar ABI and physical cursor table are unchanged.
FixedLayout(varint) remains invalid. [Grow varint elements](VARINT_GROW.md) now
use the same sequential primitives. GrowShrink/Limited varint elements,
containing record/enum tails and unsigned varint length prefixes remain separate.

Literals publish their known count before evaluating elements. Each initializer
finishes before its exact encoded width is reserved, written and committed.
Fill evaluates its value once, including count zero. Same-element copies capture
the source view first, then reserve and copy each element's actual encoded bytes;
they preserve nonminimal encodings rather than decode and re-encode them.
Normal results and tuple channels retain the existing physical-suffix landing
and independent logical-prefix behavior. Ordinary ER calls keep their element-run
width bypass, while dispatched Value results keep natural narrow-length checks.

Prefix reads and whole views stay O(1): a cheap minimum-one-byte count check
validates the region without walking elements. Copies, byte extents and snapshots
use bounded sequential walks. Sparse reads may map bytes without advancing the
physical producer cursor. Rendering snapshots the exact encoded span before
later arguments run, then decodes it sequentially.

For loops use a byte cursor and the checker's binding type. A plain source loop
already binds an encoded reference for variable elements; a local value copy
decodes it. After the body or continue, the cursor advances over the old element.
When a reloadable source's base changes, the walker seeks the current ordinal
in the new source after checking its current length. Existing fixedlen and
SequenceValue rules preserve the difference between a live reference path and
an explicitly pinned `&link`. Indexing/range slices and cross-element storage
conversion remain frontend-invalid in the pinned language.

Actual varint-element nonlocal targets require dedicated image staging. The
refusal applies across optimized inline stacks as well as ordinary emitted
targets. Fixed/scalar target cancellation during array construction remains
supported. Alternative named-array replacement cannot observe the old owner
through later result expressions or opaque calls until bounded overlap is
proved; the record gate and array gate share this check. This checkpoint does
not establish untrusted-image verification or serialization.

Differential fixtures cover zero-fill effects, signed extrema, calls, inline/FV
and dispatch channels, exact tuple forwarding, copies, whole slices, reference
paths and rebinding with continue. Byte tests inspect all four prefix widths,
global defaults, normal results, raw nonminimal copies, authoritative metadata
and physical cursors. Resource probes derive near-end fill counts from metadata,
preserve a neighboring canary and repeat construction/cancellation 10,000 times.
