# Compact fixed-capacity array storage

Internal layout 8 stores a static `T[..k]` value as its smallest unsigned live
length followed immediately by its capacity slots. Length uses u8 through 255,
u16 through 65535, u32 through UINT32_MAX, and u64 above that. Fixed-value storage
has alignment one and no trailing rounding. Existing wasm32 allocation bounds
reject capacities whose storage cannot fit before multiplication or narrowing.
Runtime-limited arrays keep their existing u32 capacity/length image and separately
aligned owner controls; external scalar ABI 1 is unchanged.

`StaticLimitedLengthStorage/Bytes` defines the physical width. Shared unsigned
load/store helpers keep logical counts I32. Views and mutation use those helpers;
literals, strings and conversions publish the same width. `.len`, loops, indexes,
slices and rendering therefore read authoritative compact metadata. `.cap` stays
a type constant. String literals check character count against capacity, rather
than the allocation size that also includes metadata.

Capacity zero has a deliberate allocation exception: a standalone C value still
contains one unused element slot. Its allocation is `width + max(k,1)*sizeof(T)`;
for `u64[..0]` this is nine bytes, with elements at offset one. This placeholder
is not a proved encoded C.2 image extent: native FixedSize uses the actual zero
capacity. The frontend rejects zero-capacity fields and elements under §3.4,
and this checkpoint preserves that boundary.

Receiver evaluation, source snapshots, capacity checks, argument effects and
mutation order remain the existing language rules. Same-type fixed copies,
parameters and results inherit the compact allocation; different-capacity and
slice conversions keep their checked value copies. Unused slots are not logical
elements and default initialization does not run their element initializers.

Exact byte tests cover capacities 1, 255, 256, 65535 and 65536, unsigned metadata
loads, unaligned u64 elements, three-byte record strides and physical allocation
sizes. Host edits to valid length metadata change typed views without corrupting
elements. A standalone zero-capacity allocation test checks adjacent byte
canaries and its placeholder; separate native/direct tests retain the invalid
containing forms. Oracle fixtures cross the 255/256 mutation boundary, retain
references/slices, and exercise strings, copies, conversions and ordinary results.

No overlap proof is widened. Static-limited fields remain outside
PackedIntegerImage/ProvenEnumImage and owned image-effect admission. Compact
metadata does not prove spare-slot, interrupted-construction, replacement or
serialization equivalence. General image walkers remain separate work.
