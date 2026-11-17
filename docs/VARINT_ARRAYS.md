# Sequential varint array elements

Internal layout 11 admits standalone immutable `varint[u8/u16/u32/u64]` arrays
and whole `varint[:]` views. Metadata keeps the existing unsigned fixed width;
elements are packed signed zigzag ULEB128 images with no fixed stride. The aligned
24-byte owner controls, scalar ABI and physical cursor table are unchanged.
FixedLayout(varint) remains invalid. [Grow varint elements](VARINT_GROW.md) now
use the same sequential primitives. GrowShrink/Limited varint elements and
general containing shapes remain separate; layout 15 admits
[fixed-prefix terminal record tails](ENCODED_RECORD_TAILS.md). Layout 14 combines unsigned
varint lengths with these elements; see [combined images](COMBINED_VARINTS.md).

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

Direct Wasm keeps a byte cursor in a top-level loop over an immutable incoming
varint slice parameter when the preceding statements and the loop body only
perform eligible arithmetic, tests and writes to private numeric locals. On
entry to each subsequent iteration, the cursor skips the previous encoding.
A break or an exhausted sequence can stop before decoding the final element.
Other loops reload the view and seek the current ordinal from its beginning,
which can take quadratic time. [Measurements and controls](../bench/results/2026-11-17/varint-foreach/README.md)

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
