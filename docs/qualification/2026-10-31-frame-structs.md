# Growable-tail frame struct qualification

Implementation: `8ca8bc8`.
Release compiler SHA-256: `07d07a90cd556d3a7af5c717ef354a33d3c3b5f76bc2f480f83b1af7edcfc259`.
Debug compiler SHA-256: `e87744f74b1157b847faa6d6eb454c2a55fcdd082e2225df03e98cef8dd1bb95`.
Prepared Release headers match the implementation commit byte-for-byte.

- Full Release differential suite **2383/2383 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- Focused Debug differential suite **50/50**.
- Resource suites **39/39**, sessions **11/11**, owned-struct boundaries **4/4**
  and dynamic boundaries **4/4** on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

Frame objects with fixed prefixes and one fixed-element growable/shrinkable tail
preserve the native named-return rule: prefixes and lengths are snapshots, while
tail elements share receiving storage. Whole-object reconstruction pins the
receiver and writes fields in declaration order. Interrupted prefix initializers
preserve later fields; omitted optional references become null when reached.
Coverage includes fixed aggregate elements, recursive forwarding, inline/mixed
returns, global defaults and tail assignment.

Repeated-call tests distinguish dying private headers from surviving borrowed
headers, validate abandoned advertised extents, preserve neighboring canaries
and release anonymous owners under a three-page limit. An initially immutable
test parameter was corrected to `var`; the final 39-test suite passes in full.
Astra reviewed the implementation and found the prefix-initialization issue
before qualification; the field-order fix is included in the implementation.

Nested owners are a separate subsequent slice. Packed images, variable elements,
multiple tails, rendering and comparison remain outside this milestone.

Reports/logs: `build/frame-struct-release-*`,
`build/frame-struct-debug-final-*` and `build/frame-struct-debug-*`.
