# Record padding

Internal layout 9 supports padding in fixed structs and standalone variants,
and before the final owned tail in supported non-frame variable records.
Declarations retain their field indices; pads have no type or initializer.

For a fixed record, `pad n` adds exactly n bytes. Bare `pad` rounds the current
offset to the next real field's native PadAlign, skipping intervening pads:
integer/float width, eight for plain references and slices, one for bools and
aggregates. No final rounding is added. A trailing bare pad adds zero bytes.
Parent packing does not change each field's representation: direct plain
references still occupy four bytes even though a preceding bare pad aligns to
eight. Record extent arithmetic checks the configured memory limit before any
narrowing. Empty standalone records retain a one-byte allocation placeholder.

Variable record image construction follows the pinned byte producer: explicit
`pad n` writes n zero bytes at that declaration position; bare pad writes none.
It reserves and publishes each pad only after earlier initializers complete and
before evaluating later fields. Prefix offsets and persistent typed views use
that same image layout. Controls remain separately aligned and contain no pad
data. Existing whole-image copies include explicit padding and capacity bytes.

Pad-only enum alternatives use semantic EmptyLayout: bare/zero pads encode no
payload, while a positive explicit pad contributes its full extent. Fixed copies
preserve padding bytes, including bytes edited by a host. Fresh fixed temporary
storage may be zeroed; padding does not become a logical field.

The pinned native variable-enum producer distinguishes a literal field stream
from a copied fixed variant when a bare pad introduces a gap. This checkpoint
refuses such fixed payload alternatives in `E..`. Bare pads without a gap and
explicit-only fixed payloads remain supported. Padded frame objects and padding
after an owned tail require separate walkers and are also refused. Existing
byte-overlap and owned image-effect proofs still exclude padding; successful
ordinary construction does not widen either proof or establish serialization.

Tests cover leading/consecutive/trailing pads, generic layouts, references,
slices, bools, floats, nested arrays, defaults, globals, copies, ordinary/inline
callbacks, pad-only alternatives and persistent variable-prefix references.
Byte tests on V8 and Wasmtime inspect offsets, cursor sizes and host-modified
copy bytes. Resource tests check declaration-order exhaustion and repeated-call
canaries; refusal tests cover the remaining shapes and extent overflow.
