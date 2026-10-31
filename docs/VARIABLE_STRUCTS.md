# Owned structs with one array tail

This implements the first containing-value slice from the Astra xhigh plan:
standalone `SC_VARIABLE` structs with supported fixed-layout fields followed by
one final fixed-element `T[]`/unsigned-length or runtime-capacity `T[..]` field.
Frame objects with a final `T[>..]`/`T[>..<]` field use the same control-layout
walker with different named-return and assignment rules.
The final field may also be another supported owner, recursively, while every
earlier field remains fixed-layout. Each chain still ends in exactly one array.
Standalone variable-size variants share this record walker and may appear as
final non-frame owner fields; their nominal identity remains distinct from structs.

`RegionOwner` governs allocation, parameters, receiving channels, temporaries and
cleanup. `RegionArray` remains specific to sequence operations and element runs.
Aligned `ControlLayout` objects hold whole/nested owner references and the embedded
24-byte terminal array control. A separate `RecordImageLayout` describes packed
prefix offsets and size. The owner remains `SC_VARIABLE`; `FixedLayout` still
refuses descriptor copies.

Each live owner acquires one stable data region. Non-frame records now store
`fixed prefix | array prefix | elements/capacity` together in that region.
Fixed fields retain their current target representation. `RecordFieldAddress`
locates prefix fields through the terminal control's immutable logical image
anchor; references to prefix fields and elements point into stable region data.
References to whole/nested owners and the final array field still name controls.
This works for globals, caller results and references retained across calls
without persistent activation mappings. Frame field addressing remains separate.

Construction evaluates each fixed field and then appends its captured value at
the current physical cursor. Omitted defaults commit at their declaration
position. The final owned field constructs through a private producer control;
its physical start can differ from the logical terminal prefix. Decoding reads
the receiving anchor rather than repairing it from the producer's cached count.
Nested final records use the same rule. Captured same-type copies snapshot the
source anchor and complete logical image extent, including Limited capacity,
then copy those bytes independently.

Normal alternate returns land the entire physical record suffix when an open
construction requires it, then decode fields and the terminal prefix at their
original packed offsets. Named record returns alias their receiving image:
later result expressions can change an earlier result's prefix and tail data.
By-value parameters remain independent objects. Blocks, branches, loops, matches,
ordinary/inline calls and mixed results use the same receiving channels.

Growable-tail frame objects keep a private prefix and tail header while sharing
their receiving tail's stable base/limit. Every named return copies prefix bytes
and publishes the current length; later prefix/length changes do not change an
earlier result, while mutations to shared elements remain visible. Whole-object
assignment pins its receiver before evaluating the RHS and reconstructs it in
place. Prefix writes occur in declaration order, so an early exit leaves fields
whose initializers have not run intact. Omitted optional fields become null at
their own position. Private embedded headers die with their logical scopes;
surviving borrowed/global headers validate an abandoned advertised tail extent.

Qualified boundaries remain explicit: nonfinal owners, multiple variable fields,
variable elements, whole-variable-object assignment,
variable-struct rendering/comparison, serialization and relative references remain
outside this slice. Whole-record image nonlocal targets are still gated. The frontend rejects views escaping private by-value parameter storage.
Declared global defaults are checked initializer nodes; explicit
`default<NonfixedStruct>()` remains frontend-invalid.

Variable-element arrays still need further containing-value walkers. Variable
variants embedded in enums now place their complete record image after the
existing tag/control union; the whole enum retains its separate internal layout.
See [record images](RECORD_IMAGES.md) for the byte contract and remaining gates.
