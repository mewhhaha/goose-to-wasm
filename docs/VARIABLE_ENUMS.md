# Nonresizable variable-mode enums

Internal layout 7 gives `E..` a compact u8/u16 tag followed by its active payload
only. Empty alternatives occupy only the tag. Fixed-mode enums retain a tag and
maximum fixed payload; standalone empty variants retain their one-byte placeholder.
Underlying fields retain their current target representation, so this migration
does not establish a general serialized or cross-pointer-width image ABI.

Each owner has one data region and a separately aligned control envelope. Its
common 24-byte header precedes one persistent control allocation for every
nonfixed variant. These allocations are summed, not reused as a maximum union.
Fixed payload views point directly behind the image tag; nonfixed payload views
point to their own control slot, with the record anchor at that same image
address. Seeding a requested view checks no inactive extent. Access/copy validates
its typed image when needed. A saved old variant reference retains its own prefix
and tail offsets after another variant replaces the bytes. It does not recheck
the current tag before each field access.

Construction appends and commits the tag first. Fixed fields evaluate before
reserving and committing their bytes, in declaration order. Nonfixed payloads
use private producer controls sharing the region; persistent receiving views
retain their logical anchors. No inactive payload bytes are cleared or reserved.
An Empty value therefore fits even when another alternative has a very large
payload. Active image extent is checked and mapped independently of the physical
cursor. Sparse decoded extents never promote that cursor.

Same-mode copies snapshot the source anchor and active extent, then copy those
bytes independently, including runtime-limited capacity. Control envelopes are
never copied as values. Fixed-mode and standalone fixed-variant producers keep
fixed snapshot semantics. Variable-to-fixed conversion allocates a fixed
activation snapshot and copies only the active encoded bytes; it cannot reuse a
short Empty image as the maximum fixed union.

Normal results stage in private control envelopes sharing the receiving region.
All attempt starts are captured before producer evaluation. The complete physical
suffix lands only when the native syntactic open-construction rule requires it;
otherwise the original receiving anchor remains authoritative. Completion decodes
that anchor. A named Ident already occupying its result channel keeps its shortcut.
Tuple forwarding stages each image independently, captures every returned Wasm
value, then finishes original receivers. Fixed enum/variant and borrowed ADT
tuple results adapt their captured values after the call. Contextually adapted
plain variant-reference calls prepare the tag before arguments; explicit copy
keeps its source-evaluation-before-tag ordering.

Single variant call adaptation follows the final checked expression annotation,
not merely its natural specialization result type. The checker can leave a call
unadapted when an argument never returns, and that call must write no tag before
the canceled argument. Adapted ordinary calls and inline bodies commit tags
before arguments/inline parameter initializers. Construction opening is separate:
ordinary construction opens its destination, an InlineBlock does not acquire
that extra opening, and forwarded nonfixed variant tuple channels open explicitly.
The permanent oracle matrix records the native O0/O2 differences caused by
inlining; they are not repaired into a different abstract result.

Matches evaluate the owner once. By-value nonfixed payload bindings acquire an
independent region; borrowed bindings use persistent owner controls. Dispatch
retains its argument timing: shared arguments evaluate once, fixed payload values
snapshot at scrutinee evaluation, nonfixed value cases copy the enum into the
existing argument region, and references retain the original owner. The variable
dispatch tag is read at its native point after shared arguments.

Abandoned-construction guards use the compact tag width. Dying-owner interior
recognition covers the extended control allocation, not the image bytes. Private
producer registrations remain scoped, and pending cleanup retains dying-owner
evidence until every abandoned extent check completes. Surviving global/caller
owners still enforce resource bounds.

Nonempty replacement observed through old named payload references qualifies
only for proved packed integer fixed payloads or qualified integer-prefix record
images with supported terminal elements. Other representation-sensitive overlap
shapes retain their gate. Resizable enums, multiple/nonfinal variable fields,
variable elements, containing `E..` owners, general enum nonlocal targets,
serialization, recursive rendering and comparison remain subsequent work.
Explicit `default<E..>()` remains frontend-invalid; checked globals use the first
variant's declared defaults. Optimized local exits are distinct from unsupported
actual out-of-line enum effect targets.
