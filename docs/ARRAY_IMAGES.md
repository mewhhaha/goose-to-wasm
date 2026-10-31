# Unsigned array value images

Internal layout 4 separates the physical form of an array from its natural
function result type. The scalar host ABI remains version 1. Each separately
aligned owner control contains six u32 words:

| Offset | Meaning |
|---|---|
| 0 | Raw element base / derived image element base |
| 4 | Raw logical length / cached image length |
| 8 | Immutable physical region limit |
| 12 | Raw capacity / cached image capacity |
| 16 | Receiving image anchor |
| 20 | Physical mode |

Modes distinguish raw elements, Var u8/u16/u32/u64 length prefixes, and
runtime-limited capacity/length prefixes. Default Var lengths use u32. Image
accessors read authoritative metadata and derive the element base; cached words
do not replace the image. Access validates the represented extent against its
physical region, including capacity and length consistency for limited arrays.
The validated logical extent is mapped into linear memory even when a canceled
producer committed only its prefix. Limited images map their capacity extent;
mapping leaves the physical construction cursor unchanged.
Grow/GrowShrink and element-run channels retain raw base/length semantics.

Var values are `[unsigned length][elements]`. Runtime-limited values are
`[u32 capacity][u32 length][capacity slots]`. Their prefixes precede element
effects; capacity expressions run before the capacity header is written. Copies
capture their source before initializing a receiving image. Same-type limited
copies preserve the capacity extent. Existing limited assignment constructs its
RHS first, preserves receiving capacity, and copies live elements afterward.

Ordinary calls evaluate arguments before preparing result channels. Same-width
Var values construct directly. A Var element-run producer targeting another
length width reserves that receiver's prefix, writes raw elements through a
frame-only adapter, and patches the count after success. A normal Var producer
without an element-run form uses an image adapter on the same region; after the
pending-effect check, adaptation slides the entire suffix over its prefix or
adjusts the prefix width. A Grow result targeting a Var value uses a natural
temporary region, followed by prefix construction and a copy after success.
Inline and function-value receiving-form rules remain distinct.

Named Var values alias their receiving image. A named growable local targeting
a Var result reserves that result's prefix at declaration, shares its elements,
and patches its count at return. Normal result staging keeps the receiving
anchor separate from the current producer start. Native construction-state rules
determine when the full suffix lands over that anchor. Metadata is then decoded
at the receiving anchor, including any canceled prefix retained there; the
winning producer's cached count must not repair those bytes. Runtime-limited
normal returns use the same rule, preserving observations through saved element
references after an alternate named return.

The per-region cursor/publication runtime now applies to image construction even
without an actual nonlocal target. These controls and adapters add activation
storage; adapters alone acquire no data region. Region bounds and cleanup remain
explicit, including the natural Grow-to-Var temporary.

This slice covers currently admitted fixed-layout elements. Their own
representations remain target-specific. Terminal array images inside existing
single-tail records/enums do not make those enclosing values C.2 images.
Varint lengths, variable elements, general image walkers, serialization,
and `bytes_of` retain their separate gates. Standalone scalar and recursively packed
integer aggregate array image nonlocal targets use the
[effect landing contract](NONLOCAL_RETURNS.md#array-image-targets). Other aggregate
element representations and enclosing record/enum image targets remain gated.

Evidence includes cross-backend construction, named-return alias and no-element-
run adaptation cases, plus direct V8/Wasmtime checks of exact prefix bytes,
packed element strides and authoritative metadata reads. See
[the layout migration](IMAGE_LAYOUT.md) for the fixed-record overlap proof.
