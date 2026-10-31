# Internal layout migration

The `goose.direct` producer marker distinguishes external scalar `abi=1` from
internal `layout=6;enum-tags=compact;variable-enums=control-union`, alongside
`record-values=packed-single-tail;owner-control=24` and
the unsigned array value and packed fixed-record/variant markers.
Compiler identity invalidates cached complete modules when layouts change.
The 24-byte owner control ABI remains separately aligned as described in
[TARGET.md](TARGET.md); it is not a serialized image.

Fixed structs and standalone variant payloads place fields next to each other,
without inter-field or trailing alignment. Each field retains its own current
representation. A `u8` followed by a `u16` occupies three bytes with alignment one;
fixed arrays use that stride. This applies recursively through nested and generic
fixed records. Wasm permits the resulting unaligned scalar loads and stores.
Empty standalone records retain a one-byte allocation placeholder. That placeholder
does not establish their native image extent, so embedded empty records remain
outside the byte-overlap proof. Zero-length array fields are frontend-invalid.

Enum tags use u8 through 256 variants and u16 above that. Fixed-mode enums
place the maximum encoded payload immediately after that tag, without trailing
alignment. Empty alternatives contribute zero payload bytes while standalone
empty variant values retain their one-byte placeholder. Constructors, conversions,
matches, dispatch and abandoned-payload guards share width-aware tag accessors.
This layout preserves relative overwrite observations between variants when
every field recursively consists of fixed-width integers, nonempty
fixed arrays, or nonempty fixed structs/standalone variants without explicit
padding. Empty outer alternatives remain valid. Tests cover both overwrite
directions, signed values, nested offsets, generic array strides, saved field
references, ordinary/inline results and owned storage paths.

Other payloads remain outside that proof. Static-limited arrays retain their
length/header layout; nested fixed enums remain outside the recursive integer
overlap proof despite their compact tags; references and slices
use the direct target's wasm32 representation. Bool, float, varints and embedded
empty aggregates remain gated for replacement overlap. Packing their parent
does not establish compatibility for those fields. Fixed-array extent checks
reject oversized counts before multiplication, including odd packed strides.

[Array values](ARRAY_IMAGES.md) now place unsigned lengths or capacity/length
prefixes in their region and read that metadata through physical-mode accessors.
Their fixed-layout elements retain the target representation.
[Single-tail non-frame records](RECORD_IMAGES.md) now store packed prefixes and
terminal array images together. Their aligned controls remain separate, and the
outer variable enum retains its aligned maximum control union. Its compact
tag does not establish the C.2 tag-plus-active-payload layout. Further steps are
compact static-limited metadata and general contiguous variable images. Those require dynamic
walkers, including partial construction and canceled nonlocal returns,
before variable elements, nonfinal variable fields, relative references,
serialization or general byte-overlap parity can qualify. Reference-containing
overlaps expose platform-specific address bits; width changes alone do not make
native/memory64 and wasm32 addresses equivalent.
