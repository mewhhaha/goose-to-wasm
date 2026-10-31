# Nested single-tail owner qualification

Implementation: `26aee82`.
Release compiler SHA-256: `3c0b313a8d19c855255baa384876eadeb647dc0cc6933cb8faba9f8802a8a94c`.
Debug compiler SHA-256: `b721f346c31f25cfce3a71b41ddc13363a9ede1d6350de913eadadadf8f830ed`.
Prepared Release headers match the implementation commit byte-for-byte.

- Full Release differential suite **2423/2423 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- Focused Debug differential suite **40/40**.
- Resource suites **41/41**, sessions **11/11**, owned-struct boundaries **4/4**
  and dynamic boundaries **4/4** on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

Fixed-prefix owner chains recursively reach one terminal supported array. Tests
cover two/three nesting levels, generic fixed elements, owned copies/parameters,
retained inner-prefix references, recursive forwarding, control results,
interrupted inner reconstruction, narrow terminal lengths and runtime capacity.
Mixed-return tests preserve whole-object aliasing for variable owners and prefix/
length snapshots with shared elements for frame objects.

Repeated calls under a three-page limit prove one region per live owner.
Cleanup records the ultimate embedded header: dying private nested headers can
be abandoned, while surviving borrowed headers validate their advertised extent
and preserve the next region's canary. Astra reviewed the layout recursion and
native prefix/tail rules without finding a blocker.

Nonfinal owners, multiple variable fields, variable elements, variable-mode enum
containers and packed images remain outside this slice.

Reports/logs: `build/nested-struct-release-*` and `build/nested-struct-debug-*`.
