# Runtime-capacity array qualification

Implementation: `b6da25a`.
Release compiler SHA-256: `ba5260bf5fa30efbbc2cfdf979aab52bdb43a92609138f791ef20de54730405d`.
Debug compiler SHA-256: `04f081466d795b0deed1ea593a122fbdb565f9c29512ca9f9a8a31d355f73cab`.
Prepared Release headers match the implementation commit byte-for-byte.

- Full Release differential suite: **1483/1483 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three explicit compile refusals.
- Debug runtime-limited cases **160/160**; existing dynamic-result cases **72/72**
  on both direct engines.
- Resource suites **31/31**, compiler sessions **11/11**, and boundaries **4/4**
  on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13**, and
  static-data checks **4/4**. The extension suite's obsolete runtime-capacity
  refusal was replaced by the remaining varint-length boundary and rerun.

The uniform 16-byte internal region header separates logical capacity from the
physical region limit. Coverage includes spare-capacity copies, cross-kind
construction, whole-header named-result aliases, ordinary/inline and mixed/
forwarded results, and static-limited receiving ordinals. Scalar and fixed
aggregate elements, retained references, pop/refill and self-slice assignment
agree with the oracle. Capacity-literal effects and range errors survive
inlining, branch folding and conversion to other receiving array types.

Repeated calls cover pinned receivers, reference retargeting during RHS
evaluation, early RHS exits, capacity preservation and scope release. Capacity
and physical-reservation overflow preserve neighboring-region canaries.
Astra reviewed ownership, cleanup, result adapters and named-result header
aliasing read-only; no blocker remained.

Scope remains supported fixed-layout elements; variable fields/elements, other
variable-array length encodings and packed image compatibility are subsequent
work. Logs/reports: `build/runtime-limited-*`.
