# Fixed-payload variable-mode enum qualification

Implementation: `2827546`.
Release compiler SHA-256: `66a05461d2c4933ec1773c3a6521f25c89fee0576c6d5c82315b16a00d96c7bc`.
Debug compiler SHA-256: `ff9f4683d0f875e55aa8976868043d252184e917d6377c79eaa6dfe98245e8b2`.
Both prepared compiler trees matched the implementation headers byte-for-byte.

- Full Release differential suite **2443/2443 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- Focused Debug differential suite **20/20**.
- Resource suites **45/45**, sessions **11/11**, enum boundaries **5/5**,
  owned-struct boundaries **4/4** and dynamic boundaries **4/4** on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

Variable-mode enums retain SC_VARIABLE and own independent stable region images;
their control descriptors never enter fixed-copy paths. The qualified image has
a u32 tag and fully initialized maximum fixed-payload union. Tests cover generic
payloads, declared defaults, fieldless constants, ordinary/inline/recursive and
mixed results, whole-image named aliasing, mode/variant adaptations, by-value
payload snapshots and explicit by-reference payload matches.

External references and slices keep their referents across image copies and
owned parameters while fixed payload fields stay independent. Declaration-order
effects and temporary payload borrows surviving later arguments match native.
Repeated calls release regions; oversized maximum-union reservation preserves
field effects and a neighboring canary under a three-page memory limit.

Astra reviewed the ownership gates, image initialization, result channels and
matching semantics. Nonfixed payloads, containing E.. owners, serialized images,
rendering and comparison remain outside this implementation commit.

Reports/logs: `build/variable-enum-release-*`,
`build/variable-enum-debug-final-*` and `build/variable-enum-debug-resources.log`.
