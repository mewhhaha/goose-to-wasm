# Standalone variable-size variant qualification

Implementation: `2116462`.
Release compiler SHA-256: `861ba96674c94e42872d31bbb717a4f3a2f8f5ccd7bb07d93969c459da511ddd`.
Debug compiler SHA-256: `f51b27fe8c822b405973a164c1eeae94870e71096a4f4a79f050e8fc751826c1`.
Prepared Release headers match the implementation commit byte-for-byte.

- Full Release differential suite **2483/2483 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- Focused Debug differential suite **40/40**.
- Resource suites **49/49**, sessions **11/11**, standalone-variant boundaries
  **4/4**, enum boundaries **5/5**, owned-struct boundaries **4/4** and dynamic
  boundaries **4/4** on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

The record walker now supports standalone SC_VARIABLE variants with fixed prefix
fields and one terminal variable/runtime-limited array. Tests include a supported
payload whose sibling is resizable, nested sibling-variant tails and struct
wrappers, independent copies/parameters, stable prefix references, mixed whole-
record NRVO aliasing, recursive/inline/control results, narrow terminal lengths,
runtime capacity and interrupted prefix/tail construction.

Repeated exported calls prove scope reuse and pinned tail assignment under a
three-page limit. Tail exhaustion preserves declaration-order effects and a
neighboring canary. Identity checks include enum instantiation, variant and
enclosing enum mode. Astra reviewed all ownership-sensitive record gates.

Resizable standalone variants, nonfinal/multiple variable fields, variable
elements, nonfixed E.. images and packed image operations remain separate slices.

Reports/logs: `build/variable-variant-release-*` and
`build/variable-variant-debug-*`.
