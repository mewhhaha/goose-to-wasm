# Variable-size array implementation

This follows the Astra xhigh review of the pinned frontend and C emitter.
Implement in these slices, retaining fixed-value copy gates throughout:

The fixed-element unsigned-length and runtime-capacity slices below are
implemented. Varint lengths and variable elements/containing values remain
subsequent work.

1. Fixed-layout elements in `T[]` and `T[u32]`: use checked stable regions,
   owned parameter/result channels, scoped temporaries, views and element writes.
   Keep the frontend's `SC_VARIABLE` classification and frozen length. Growable
   mutation and replacement assignment must not follow from using region storage.
2. Other length encodings: qualify constructor range checks, cross-kind receiving
   channels and named-result eligibility against the native emitter. Default and
   explicit u32 normalize to the same storage. Varint image layout belongs to
   the later image ABI work. Native single-result element-run paths and ordinary
   mixed results differ in where narrow length checks occur; test both explicitly.
3. Runtime-capacity `T[..]`: add a logical capacity independently of the region
   limit. Same-type copies preserve capacity; construction from other array kinds
   chooses the initial length. Assignment evaluates the RHS before writing and
   preserves the destination capacity. It permits reads of the existing owner,
   unlike growable reconstruction. Use a uniform internal control-header layout
   or explicit adapters before sharing result channels across these kinds.
4. Variable elements, fields and enum modes: introduce representation walkers
   and ownership-aware construction, rather than copying nested descriptors.

The native named-result analysis also places a growable local's element run into
an `A_VAR` result. Preserve the shared data identity when later result expressions
mutate that local, while each result keeps its separately published length.

Runtime-limited named results alias their entire receiving header, so a later
result can change an earlier result's length. Other region-backed named locals
retain private length headers. The internal region control ABI now uses 16 bytes:
base at 0, length at 4, resource limit at 8, limited capacity at 12. Fixed static
capacity arrays retain their inline layout.

The initial region representation is target-specific. It establishes no packed
image, serialization or `bytes_of` compatibility with the pinned C ABI.

Normal and element-run function forms keep the producer's prefix contract separate
from a receiving value's contract. Raw runs omit the producer's length-width check
and function-level named-result binding; local and by-value parameter construction
still checks its own width. Mixed results keep their natural checks and validate
or copy receiving ordinals after all results return. Inline bodies follow the
receiving construction request, with separate oracle expectations where the pinned
optimizer changes observable narrow-length behavior. Both forms are emitted
conservatively for eligible reachable specializations; unused forms can increase
the region bound. The varint image form is still refused.
