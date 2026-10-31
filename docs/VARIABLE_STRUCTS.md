# Owned structs with one array tail

This implements the first containing-value slice from the Astra xhigh plan:
standalone `SC_VARIABLE` structs with supported fixed-layout fields followed by
one final fixed-element `T[]`/unsigned-length or runtime-capacity `T[..]` field.

`RegionOwner` governs allocation, parameters, receiving channels, temporaries and
cleanup. `RegionArray` remains specific to sequence operations and element runs.
The separate `ControlLayout` cache describes fixed field offsets and an embedded
16-byte array header; it does not turn the variable object into an `SC_FIXED`
value. `Size`/`FixedLayout` still reject ordinary copies of its descriptor.

Each live owner acquires one data region through `TailHeaderLocation`. Private
header records likewise name the embedded header at the enclosing owner's
logical cleanup depth. References to the object/prefix address its control
storage; references to tail elements address its stable data region.

Construction visits checked fields in declaration order with `InitFor`, storing
fixed fields through the existing fixed-value path and constructing the tail as
an owned value. Copying evaluates its source once, requires the same struct
instantiation, copies only fixed prefix bytes and independently constructs the
tail. It preserves receiving base/limit and runtime capacity semantics. Whole
control objects are never zeroed or copied after region acquisition.

Native nonresizable struct NRVO aliases the whole object at its receiving
destination. Named locals therefore use an `ADDRESS` slot directly: later result
expressions can change both a previously returned prefix and its tail metadata.
By-value parameters remain independent objects. Blocks, branches, loops, matches,
ordinary/inline calls and mixed results use these same receiving channels.

Qualified boundaries remain explicit: nested owners, multiple variable fields,
variable elements, growable-tail frame objects, whole-object assignment,
variable-struct rendering/comparison and packed image operations are outside this
slice. The frontend rejects views escaping private by-value parameter storage.
Declared global defaults are checked initializer nodes; explicit
`default<NonfixedStruct>()` remains frontend-invalid.

Next, growable-tail frame objects need a private control object with a shared
tail region and prefix/length snapshots at each return. They cannot reuse
whole-object NRVO aliasing. Packed C.2 images and relative references require the
later versioned image ABI transition.
