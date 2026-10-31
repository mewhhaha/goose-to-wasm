# Unsigned varint length images

Layout 13 stores standalone fixed-element `T[varint]` arrays with an unsigned
ULEB128 count followed immediately by elements. The count has no zigzag step.
Prefix width is minimal for values constructed by the backend; reads decode
the actual count and prefix end from the image. Fixed-length metadata modes,
24-byte aligned owner controls and scalar ABI 1 remain unchanged.

Known-count literals, copies and strings reserve and write the exact prefix
before elements. Unknown-count ER receivers and named Grow-to-Var results instead
reserve exactly one byte without writing it. On successful return, prefix patch
checks its new extent, moves the entire physical suffix after that original
reservation, writes the final count and adjusts the physical cursor. It never
uses logical count times stride as the suffix size. Pending effects unwind
before patch, preserving native interrupted-construction bytes.

Control word 12 records only the original construction reservation width. It is
not refreshed from decoded bytes, including after a patch; named producers can
retain their original Grow base. Public length and element-base access always
decode image anchor at offset 16, so host changes to a count or prefix width take effect
without changing the physical producer cursor. Nonminimal prefixes can be read;
this is not the language's untrusted-image verification API.

Value-form reprefixing decodes the source's actual prefix end and moves its
whole physical suffix into the target representation. Ordinary ER calls retain
their width bypass, while Value dispatch/FV adaptations retain their natural
range checks. Existing parameter/result, whole-slice, indexing, loop, copy and
string paths share those accessors. Packed fixed elements retain their own
strides, including unaligned three-byte records.

Named Grow producers bound to a ULEB Value destination conservatively refuse
later owner observations and opaque calls. A later mutable alias can write over
the expanded prefix through the old Grow base, producing an overlong encoding.
Read-only later observations and repeated-return examples are also outside this
first proof. Actual varint-length nonlocal targets, containing arrays, combined
varint elements/lengths and static fills beyond UINT32_MAX remain explicit
frontiers. This does not widen serialization, overlap or general image-effect
proofs.

Tests inspect counts 0/1/127/128/16383/16384, prefix bytes, packed strides, known
and unknown construction, authoritative host edits and cursor separation. A host
probe pre-seeds the unknown reservation to prove it is untouched before producer
effects. Resource tests check exact-end expansion before movement, neighbor
canaries and 10,000 repeated named results. Region metadata remains the existing
conservative bound across emitted Value and ER specializations.
