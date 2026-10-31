# Variable-size array implementation

This follows the Astra xhigh review of the pinned frontend and C emitter.
Implement in these slices, retaining fixed-value copy gates throughout:

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

The initial region representation is target-specific. It establishes no packed
image, serialization or `bytes_of` compatibility with the pinned C ABI.
