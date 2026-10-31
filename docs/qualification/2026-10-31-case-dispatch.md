# Runtime case dispatch qualification

Implementation: `51c8767`.
Release compiler SHA-256: `6d83164c4a75b800fbe41c3bc726229ac496144f1c409ed353a94fb2e9f30c52`.
Debug compiler SHA-256: `b4850966fb8700d202c8f8d182bbb8d4087354131a0cbdd29ff35b4c2ddddca7`.
Both prepared source trees matched the implementation before later effect work.

- Full Release differential suite **3193/3193 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- New Debug cross-backend matrices **200/200** plus **40/40** captured-case checks,
  normal/debug frontend modes. Full Debug direct suite **1279/1279**.
- Resources **64/64**, sessions **11/11**, callback boundaries **3/3**,
  enum boundaries **6/6**, standalone-variant/owned-struct/dynamic boundaries
  **4/4 each**, on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

Arguments evaluate once and snapshot before subsequent effects. Fixed enums and
fixed by-value payloads use activation storage; variable payloads deep-copy once,
while reference cases retain original storage. Case-specific captures and common
result channels cover mixed/owned returns. Recursive reference cases consume no
payload region, and normal case indices preserve natural narrow length checks.
Captured cases after parent inlining and shared reference argument spilling pass.

Five unchanged upstream programs cover evaluation order, copied/reference arms,
resizable results, nested overloads and reference results. Resource checks retain
earlier owned results through repeated calls, reclaim variable payload snapshots
and abort on a host-corrupted tag while preserving the neighboring canary.
See [FUNCTION_DISPATCH.md](../FUNCTION_DISPATCH.md) for source provenance.

Astra reviewed argument snapshots, capture union/mapping, payload addresses,
result destinations and cleanup. The pinned frontend rejects width-changing
forwarding within recursive cycles; wider receiving types outside the cycle pass.
No additional staging refusal or planner change was needed. Out-of-line nonlocal
effects remain the next slice.

Reports/logs: `build/dispatch-release-*`, `build/dispatch-debug-qualified`,
`build/dispatch-debug-captured-qualified` and `build/dispatch-debug-*`.
