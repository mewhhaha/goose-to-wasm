# Single owned growable-result qualification

Implementation: `7dee451`.
Release compiler SHA-256: `170582a1576d9b819c027159564082dfc4bdd07cf07c3844585aef587667bbca`.
Debug compiler SHA-256: `c3b92dc498b48c8b3aa4844e400e9825f27560fd237376f1e09186a211fe5474`.
Prepared Release headers match that implementation commit byte-for-byte.

- Full native/C-Wasm/direct differential suite: **1133/1133 observations** at
  O0/O2 on V8 and Wasmtime, including three explicit compile refusals.
- Focused Debug native/direct owned-result suite: **24/24** observations.
- Resource tests: **8/8 suites** on both engines at O0/O2, including 10,000
  exported calls and a recursion-depth-independent result-region bound.
- Backend extensions **100/100**; static-data tests **4/4**; compiler sessions
  **11/11** on both builds; checked scalar-cache tests **13/13** on Release.
- Valid-language unsupported lifetime boundaries: **3 sources at O0/O2**.

Coverage includes global and sibling receivers; literals, locals, fixed/limited
results and slices; grow/shrink adaptation; conditional and explicit returns;
recursive/mutual forwarding; interrupted constructors; nested inline returns;
and fixed elements carrying references/slices to surviving caller data.
The persistent-worker regression alternates owned results with other source
overlays in one worker. Astra reviewed destination routing and cleanup read-only.

Reports/logs use `build/owned-results-*`. This slice leaves owned parameters,
mixed/multiple dynamic results, anonymous owners, general control-expression
destinations, whole-owner assignment and variable-element storage for later work.
