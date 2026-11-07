# Native bounded self-relative runs

The native backend admits a narrow growable array of variable Row images: fixed-width integer/bool fields, explicit padding, fixed-width nonoptional self links to the exact Row, and a terminal `u8[]` tail (including unsigned-varint length storage). Each self link must be initialized with literal `self`. Its resolution validates the exact Row start and complete bounded Row body.

A newly admitted array uses an auxiliary `GRunRoot` frame: the ordinary 24-byte `GArray` header followed by a committed end pointer (32 bytes on the qualified native target). Ordinary arrays and references keep their existing 24-byte and 8-byte layouts. This auxiliary frame is receiving metadata, not a serialized Row image or a foreign ABI promise.

The count and committed end describe exactly the completed logical rows. Readers walk that bounded span and require an exact final end. Capacity and the region's working stack top grant no read authority. A Row view stores its own exact start/end, so later growth cannot enlarge a held view.

Fresh rows construct directly at the receiving region's committed end. A temporary GImage descriptor names that same region; it owns no separate byte storage. Fields and the terminal text construct in declaration order, with calls and branches forwarded to that descriptor. Push publishes the count/end only after validating the complete Row. Whole assignment clears the receiver before constructing the RHS. Internal result adaptation may reuse the same receiving root; it does not copy fresh run bytes from another root.

Nonoptional natural-reference parameters receive a typed hidden root capability. The raw reference must name that exact receiver. Named receiving results and immutable aliases preserve that capability. Arbitrary references cannot reconstruct it from adjacent memory. Optional references may still be tested for null without gaining data authority.

Admission remains bounded. Nested run owners, arbitrary links to other rows, captured or escaping root references, encoded root references, source copies, unsupported array operations, foreign crossings, and root-bearing programs using threads remain refused. Programs that construct these Row images and emit nonlocal return frames, and local exits that abandon an open Row construction or replacement RHS, are conservatively refused until partial-destination handling is modeled. Declared but unconstructed Row types do not trigger the nonlocal restriction, so scalar null tests remain supported. In particular, canceled whole replacement does not promise restoration of old contents. The earlier separate-storage transaction experiment was rejected against the primary construction contract.

Validation currently scans committed rows on each push and repeatedly walks from the start during foreach. Construction and traversal can therefore be quadratic in row count. This is a disclosed complexity cost; no runtime speedup is claimed.

The native runtime header is embedded in the compiler source and included in compiler/bootstrap input fingerprints. Changed compiler identity and complete generated C bytes distinguish the new representation. No Wasm producer-marker or broad external ABI change is implied by this native-only admission.
