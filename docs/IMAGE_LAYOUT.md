# Internal layout migration

The scalar-proof path emits a `goose.direct` producer marker distinguishing
external scalar `abi=1` from
internal `layout=15;encoded-record-tails=terminal;encoded-arrays=combined;array-lengths=unsigned-uleb;varint-elements=sequential-grow;varint-records=sequential`, with
`record-padding=fixed-alignment-variable-explicit` and
`static-limited=compact-lengths;enum-tags=compact` and
`variable-enums=active-payloads`, with the bounded
`resizable-payloads=descriptor-tail;resizable-prefix=frame` exception below, alongside
`record-values=packed-single-tail;owner-control=24` and
the unsigned array value and packed fixed-record/variant markers.
Compiler identity invalidates cached complete modules when layouts change.
The 24-byte owner control ABI remains separately aligned as described in
[TARGET.md](TARGET.md); it is not a serialized image.

Fixed structs and standalone variant payloads place fields next to each other,
with alignment introduced only by explicit pad declarations. Each field retains its own current
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

Other payloads remain outside that proof. Static-limited arrays now use minimum unsigned length prefixes but retain their
separate spare-slot proof boundary; nested fixed enums remain outside the recursive integer
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
outer variable enum stores the compact tag and active payload only, subject to
the resizable frame exception below. Aligned
owner envelopes retain separate persistent controls for each nonfixed variant,
so saved typed views survive replacement. Inactive payloads consume no data bytes.
[Varint array elements](VARINT_ARRAYS.md) use sequential cursors and raw encoded
copies with existing fixed unsigned metadata. [Grow elements](VARINT_GROW.md)
use raw images and direct private-count append. Containing forms and
[Unsigned varint lengths](ULEB_LENGTHS.md) now support standalone fixed elements
with known-count prefixes and successful-return suffix patching. Combined
variable elements and containing forms remain separate. [Varint record images](VARINT_RECORDS.md) use sequential field/extent walks
and a root control. Containing byte records and image
effects require further walkers and overlap proofs.
[Record padding](RECORD_PADDING.md) distinguishes fixed alignment pads from
explicit-only variable prefix pads. Frame/suffix pads, ambiguous bare-pad fixed
payloads in variable enums, overlap and image-effect proofs remain bounded.
[Static-capacity arrays](STATIC_LIMITED_IMAGES.md) now pack their minimum length
metadata and inline allocation, including standalone zero-capacity placeholders.
Further steps are general variable walkers. Those require dynamic
walkers, including partial construction and canceled nonlocal returns,
before variable elements, nonfinal variable fields, relative references,
serialization or general byte-overlap parity can qualify. Reference-containing
overlaps expose platform-specific address bits; width changes alone do not make
native/memory64 and wasm32 addresses equivalent.

Resizable enum payloads that end in a growable array keep their fixed prefix and
array count in the existing persistent variant descriptor. Their separate image
contains the compact tag and the raw logical tail bytes; these bytes alone do not
encode the count. Nested record and enum tails carry and rebase the same descriptor
metadata on construction, assignment and result adaptation. No persistent control
is reconstructed from raw tail bytes.

A containing record with this metadata keeps its fixed fields canonical in its
frame, so a tail replacement preserves references into that fixed prefix. A request
for a contiguous physical snapshot packs the current frame prefix and tail into a
new allocation. This can add allocation and copying work; this correctness repair
makes no runtime speed claim. Resizable values remain excluded from array elements
and serialized element images, and the region backend admission is unchanged.

The extra producer feature fields describe this internal exception without changing
external `abi=1`, the 24-byte owner control, or the ordinary `layout=15` image rules.
That marker is emitted only by the scalar-proof path; owned-value modules omit it,
including debug builds. Their cache safety rests on compiler identity and complete
module bytes. The build driver disables source-build caching and records compiler
and module SHA-256 identities. The Wasmtime host compares complete module bytes
for its in-process cache, so changed owned-value code receives a distinct identity.
