# Combined encoded arrays

Layout 14 admits standalone `varint[varint]`: a minimal unsigned ULEB128 count
followed by sequential signed zigzag ULEB128 elements. The two decoders share
bounded ten-byte reading without sharing signedness. Controls remain 24 bytes
and external scalar ABI 1 is unchanged.

Known-count construction reserves its exact prefix before evaluating elements.
Unknown-count ER and named Grow producers reserve one untouched byte, then move
the entire physical suffix when successful count patching changes prefix width.
Cancellation retains the established partial-byte and logical-count behavior.
Copies construct canonical count prefixes and preserve encoded element bytes,
including nonminimal element encodings. Public count/base access decodes bytes;
host changes do not advance producer cursors.

Whole slices, sequential loops, checked reference bindings, source rebinding,
rendering snapshots, normal/FV/dispatch results, mixed tuple forwarding and
Grow conversions reuse the existing encoded-element contracts. The pinned
frontend forbids indexing variable-size elements; random access requires a
separately maintained reference array.

Layout 15 adds [fixed-prefix terminal record tails](ENCODED_RECORD_TAILS.md).
Other containing shapes, actual encoded nonlocal targets, unproved named-Grow
later observations and cancelable Value-to-raw landings remain explicit gates.
This combination does not extend serialization or untrusted-image validation.

Native oracles cover lengths around 127/128 and 16383/16384, signed width
boundaries, callbacks, cancellation, tuple forwarding, copies and live views.
Host byte checks cover nonminimal count/element copies and cursor separation.
Resource checks repeat named Grow returns 10,000 times and exhaust prefix
expansion before movement, preserving a neighboring region canary.
