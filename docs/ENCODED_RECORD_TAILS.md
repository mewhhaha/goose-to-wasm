# Terminal encoded arrays in record images

Layout 15 extends fixed-prefix non-frame records and standalone variants to
terminal arrays with signed varint elements, unsigned ULEB counts, or both.
Nested single-tail records retain their fixed prefix offsets and share the
terminal array control. The existing aligned owner-control and scalar ABIs
remain unchanged.

Record decoding obtains ULEB prefix ends from bytes. Extent calculation walks
the actual encoded elements rather than inventing a stride. Copies preserve
the complete logical record image, including encoded count and element bytes;
normal result landing still moves the complete physical suffix. Copies and
ordinary, inline, FV, dispatch and tuple channels use those common operations.
Prefix field references retain their existing stable byte addresses.

Construction evaluates and commits each fixed prefix field before constructing
the terminal array with a private control in the same region. Successful
unknown-count tail production expands its prefix around the whole physical
suffix. Exhaustion checks precede movement. Recursive result forwarding does
not acquire another data lease. The pinned frontend freezes these records after
construction, including their encoded tail shape.

This checkpoint keeps variable-prefix records, frame varint tails and containing
variable enums gated. Actual encoded record nonlocal targets are refused across
ordinary and inline stacks; they need their own staging proof. Named record
replacement conservatively refuses later observations and opaque calls.
Serialization, verification and general variable-field reference identity remain
separate work. Host probes intentionally edit bytes outside the verifier API.

Native oracles cover defaults, nested prefixes, standalone variants, copies,
ordinary/inline/FV/dispatch results, mixed tuples, Grow-produced tails and
callback cancellation. Byte probes check contiguous images, saved prefix
references, changed count widths, nonminimal image copies and cursor separation.
Resource checks repeat recursive returns 10,000 times and preserve a neighbor
canary on exact-end prefix-expansion failure.
