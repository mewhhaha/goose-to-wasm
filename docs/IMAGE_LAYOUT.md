# Internal layout migration

The `goose.direct` producer marker distinguishes external scalar `abi=1` from
internal `layout=2;variant-payloads=packed-fields`. The unchanged 16-byte owner
control ABI is described separately in [TARGET.md](TARGET.md). Compiler identity
continues to invalidate cached complete modules when layouts change.

Fixed standalone variant payloads now place fields next to each other, without
inter-field or trailing alignment. Every field retains its own current
representation. A `u8` followed by an `i64` therefore occupies nine bytes and has
alignment one. Arrays use that packed stride; containing structs respect the
variant's new size/alignment. Wasm permits the resulting unaligned scalar loads
and stores. Empty standalone variants keep a one-byte placeholder allocation;
their enum constructors write no payload fields.

The outer fixed enum still has an internal u32 tag and payload offset four.
That common translation does not affect relative overwrite observations between
variants. The compiler permits a nonempty named replacement observed through an
old payload reference only when every variant contains fixed-width integer fields
or is empty. This bounded proof reproduces pinned packed byte overlap, including
mixed widths, signed values, both overwrite directions and inline results.

Other payloads remain outside that proof. Fixed structs still have their previous
field alignment; static-limited arrays still use their previous length/header
layout; nested fixed enums still have u32 tags; references and slices use the
direct target's wasm32 representation. Bool, float and aggregate payload overlap
remain conservatively gated while their byte-level contracts are qualified.
Packing a parent alone does not establish compatibility for those fields.

Further steps are recursive packed fixed records/array strides, compact fixed
metadata with centralized tag/length access, and deliberate contiguous variable
images. The latter must replace detached control headers with dynamic image
walkers before variable elements, nonfinal variable fields, relative references,
serialization or general byte-overlap parity can qualify. Reference-containing
overlaps also expose platform-specific address bits; width changes alone do not
make native/memory64 and wasm32 addresses equivalent.
