# Single-tail record images

Internal layout 5 adds `record-values=packed-single-tail`, retaining 24-byte
terminal controls and external scalar ABI 1. Supported non-frame variable
structs and standalone variants have fixed fields followed by one Var/runtime-
limited array, possibly through nested final records. Their region stores:

`packed fixed prefix | array prefix | elements or capacity slots`

Fields retain their target representation. A u8 tag, u16 word and u8[u8] tail
with two values therefore occupy `11 33 22 02 44 55`. This step does not change
plain reference widths, fixed enum tags or static-limited array representation.
General serialization and relative references remain separate work.

Aligned control layouts remain responsible for whole/nested owner references
and the ultimate array control. `RecordImageLayout` supplies independent packed
prefix offsets. The logical record anchor is the terminal image anchor minus
the record's fixed prefix size. Typed field addressing sends fixed field reads,
writes and address-of to image bytes, and final owned fields to their controls.
Fixed prefix references remain valid after calls and for globals, without
depending on live construction mappings. Frame objects retain their existing
prefix snapshot and publication paths.

Construction captures a fixed field's value, checks space, writes it at the
current physical cursor and publishes that commit. Defaults follow declaration
order. Final owned fields use private producer controls, preserving the logical
tail anchor when earlier construction left extra bytes. Typed reads always use
the original packed offsets. Same-type copies capture source anchor and decoded
logical extent before writing, then copy the entire image, including capacity.
Normal result landing moves the entire physical suffix when required and
decodes the receiving image. It does not substitute successful producer counts.

Sparse logical extents remain mapped without advancing physical construction
cursors. Variable enum payloads place their complete record image after the
existing tag/max-control union. Enum completion validates logical extent and
keeps the physical cursor left by the payload producer. The whole enum has its
existing target layout and is not declared a packed C.2 image.

This checkpoint preserves normal owned parameters/results, named image aliases,
prefix references, nested fields, callbacks, globals and active enum conversions.
Whole-record nonlocal image targets remain gated until the next checkpoint;
nonfinal/multiple variable fields, variable elements, record rendering/comparison,
varints, relative references and serialization retain their existing boundaries.

Tests inspect exact image bytes on both engines, retain global/nested prefix
references through repeated calls, and mutate stored metadata to verify typed
access. Native/C-Wasm/direct comparisons cover named tuple aliasing, prefix
effects before an interrupted callback, skipped capacity effects, and sparse
tails inside standalone records and variable enum payloads.
