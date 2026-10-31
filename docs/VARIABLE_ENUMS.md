# Nonresizable variable-mode enums

`E..` retains `SC_VARIABLE`. Its 16-byte private header owns one stable region
containing a u32 tag and an aligned maximum control union. Each variant has
supported fixed fields, or one final nonresizable variable/runtime-limited array
through a supported record chain. The terminal array's data follows that union;
its embedded header points into the same region. This is an internal control ABI,
not the pinned C.2 serialized image layout.

Preparing a payload checks the entire control prefix before deriving its tail
base. Construction writes active fields in declaration order. Omitted optional
fields become null when reached; inactive fields remain untouched. Fixed-only
literal images defer their final maximum-union reservation until after field
initializers. Images with variable payloads reserve their control union before
construction. Data limits account for the union plus terminal length/capacity.

Copies dispatch on the active tag. Fixed payload fields copy as values; variable
records copy prefixes and independently construct tails without copying owner
headers. External plain references and slices keep their referents. Runtime
capacity remains logical and independent of the region's physical limit.

Ordinary/inline/recursive calls, owned parameters, mixed results and control
channels share the owner ABI. Natural variant-returning calls construct directly
into receiving enum payloads; publication rebinds payload pointers to their outer
receivers. Named results alias receiving storage. Fixed-mode enum receivers
snapshot their fixed images. Same-instance fixed/variable/variant adaptations
remain subject to the frontend's mode and lifetime rules.

Matches evaluate the owner once. By-value variable payload bindings acquire an
independent region and release it with the arm, including arms containing only a
simple field read. Explicit `Variant &p` bindings address the image. Temporary
image lifetimes cover the containing statement and later argument evaluation.

An interrupted constructor validates its current advertised tail only when the
active tag still matches. A changed tag must not reinterpret replacement fields
as the old header. Dying private storage is recognized through its terminal or
containing enum header; surviving caller storage retains the bounds check.

Tag-only replacement returns preserve saved references into an earlier named
payload. A nonempty alternative followed by a result that may reach the named
local is conservatively refused: the native packed image can partially overwrite
those old fields, which this control layout cannot reproduce. A provenance-aware
check reports that packed enum image layout is required. Disabling named return
construction would change semantics and is not used as a workaround.

Resizable enums, multiple/nonfinal variable fields, variable elements, containing
`E..` owners, serialization, recursive rendering and comparison remain gated.
Explicit `default<E..>()` remains frontend-invalid; checked globals use the first
variant's declared defaults.
