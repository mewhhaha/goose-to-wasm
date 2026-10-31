# Sequential varint record images

Structs containing direct `varint` fields and otherwise fixed-size fields use
one aligned 24-byte root owner control and one data region. The image stores
fields in declaration order, with canonical signed zigzag ULEB128 values taking
one through ten bytes. Explicit pads contribute bytes; bare pads contribute
none in a variable image. Encoded bytes are distinct from decoded i64 values.
Varint fields are construction-only; `varint&` reads their encoded address.

The root control holds the whole image anchor at offsets 0 and 16, its region
limit at 8 and a decoded byte extent at 4. No synthetic array tail exists.
Schema walks compute field addresses and extent from the authoritative image,
so fixed fields after a varint follow its current encoded width. Saved field
references retain their earlier byte addresses. A whole copy walks its source
again before reserving and moving bytes. Normal results, named aliases and
tuple forwarding reuse the record image construction/landing protocol.

Construction encodes each initializer before evaluating the next field, checks
its complete encoded size against its region, then publishes the physical
cursor. Reads and field walks bound the encoding to ten bytes and reject
overflow or truncation. Those bounds protect access; they do not implement the
language's untrusted-image verification or shortest-encoding validation API.
Walking sparse bytes can map memory without advancing the physical producer
cursor. Default global fields encode zero as one byte.

The layout 10 marker records this representation. FixedLayout(varint) remains
invalid, and no byte-overlap or owned image-effect proof is widened. Standalone
immutable [varint-element arrays](VARINT_ARRAYS.md) now use sequential walkers;
varint array lengths, variable enum variants, containing byte records and
records that also contain variable arrays require the next general walkers.
The scalar external ABI remains unchanged.

Actual byte-record nonlocal targets are explicitly refused across ordinary and
optimized inline stacks. Canceled construction can make the original schema
decode across a later fixed prefix, exposing an overlong encoding; native's
unchecked shifts do not establish a bounded image landing contract.

Alternative returns replacing a named record cannot observe that record through
later result expressions until bounded overlap is proved. The conservative gate
also includes otherwise valid fixed-field aliases and ordinary/dispatch calls
in later result expressions, whose captures may hide aliases. In particular, an old varint
reference can land in a longer run of continuation bytes after replacement;
native's unchecked shift past 63 bits is not emulated. The frontend rejects
candidate-rooted references escaping through either tuple order or global
holders under §9.2. Ordinary saved references remain supported while their
record image is unchanged.
