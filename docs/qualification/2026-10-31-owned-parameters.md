# Owned growable-parameter qualification

Implementation: `2412d58`.
Release compiler SHA-256: `e953f4978a65e9026eb3dad25a8abf12c5e741ed47548c4f4bfde623fa7da00d`.
Debug compiler SHA-256: `32c0dcd7a37c77399510cf7d67189d1ef2f55729ce3a438de3e737778e7a6aea`.
Prepared Release headers match that implementation commit byte-for-byte.

- Full native/C-Wasm/direct differential suite: **1163/1163 observations** at
  O0/O2 on V8 and Wasmtime, including three explicit compile refusals.
- Focused Debug native/direct dynamic suite: **42/42** observations.
- Resource tests: **12/12 suites** on both engines at O0/O2, including repeated
  exported calls, later-argument return/break/continue, independent copies,
  adjacent-argument canaries and nested calls' peak live-region counts.
- Backend extensions **100/100**; static-data tests **4/4**; compiler sessions
  **11/11** on both builds; checked scalar-cache tests **13/13** on Release.
- Boundary tests **2/2**: three valid unsupported sources at O0/O2, plus three
  invalid escaping parameter references/slices rejected by both targets at O0/O2.

Coverage includes independent explicit copies, argument evaluation order,
literals/fixed/limited/owned-result sources, grow/shrink mutation, owned and
fixed multi-results from parameter-taking functions, reference-taking of incoming
headers, and valid references/slices to external data carried in fixed elements.
Astra reviewed the implementation and its narrower call-scoped lifetime boundary.

Reports/logs use `build/owned-parameters-*`. General anonymous view temporaries
need statement lifetimes; function-value ownership, mixed/multiple owned results,
whole-owner assignment and variable-element storage remain subsequent work.
