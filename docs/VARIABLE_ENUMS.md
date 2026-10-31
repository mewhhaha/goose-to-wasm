# Variable-mode enums with fixed payloads

`E..` retains `SC_VARIABLE`. A 16-byte private owner header points to a stable
region containing a u32 tag and naturally aligned payload union. The image uses
the fixed enum's target layout, including space for its largest variant; every
successful construction initializes all inactive bytes. This is an internal
representation, not the pinned C.2 serialized image ABI.

Constructors evaluate fixed payload fields in declaration order and reserve each
written prefix before storing. Final union reservation/zeroing follows those
initializers, preserving effects before a resource failure. Region metadata and
limits account for the maximum union image even when the active variant is small.
Copies transfer image bytes into independent receiving regions and preserve the
receiver's own control header. External plain references and slices in payloads
keep their referents, as fixed field value semantics require.

Ordinary/inline/recursive calls, owned parameters, mixed results and control
destinations use the existing owner ABI. Named results alias the entire receiving
header/image; later payload writes can affect earlier variable-mode results.
Fixed-mode receivers snapshot their fixed image at the result's evaluation
position. Fixed enum and standalone variant results adapt into variable-mode
receivers; variable-mode values adapt back to fixed enums of the same instance.
`Size`/`FixedLayout` still refuse the variable descriptor.

Matches evaluate the owner once and read the image tag. By-value bindings copy
the fixed payload before executing the arm; explicit `Variant &p` bindings point
into the image and follow frontend lifetime rules. Temporary image lifetimes
cover the containing statement, including borrowed payload results consumed
after later argument evaluation.

Only supported fixed-size payload fields qualify in this slice. Variable or
resizable payloads, containing `E..` owners, image serialization, recursive
rendering and comparison remain explicitly gated. The frontend rejects whole
assignment to nonresizable variable enums and views escaping private by-value
parameters. Explicit `default<E..>()` remains frontend-invalid; checked global
defaults use the first variant's field defaults.
