# Mixed owned results and named-result qualification

Implementation: `21e763a`.
Release compiler SHA-256: `13e99450a322aabfb38354548912a9602328158cf407b5a75a38704177e39c09`.
Debug compiler SHA-256: `34c8b0a3b3b5598fdc50e273bf70497512ee23070bb99186c8cc68d7270b3274`.
Prepared Release headers match that implementation commit byte-for-byte.

- Full native/C-Wasm/direct differential suite: **1193/1193 observations** at
  O0/O2 on V8 and Wasmtime, including three explicit compile refusals.
- Focused Debug native/direct dynamic suite: **60/60** observations.
- Resource tests: **15/15 suites** on both engines at O0/O2, including separate
  named-result lengths, two independent named locals, recursive forwarding of
  two receiving regions and 10,000 repeated exported calls.
- Backend extensions **100/100**; static-data tests **4/4**; compiler sessions
  **11/11** on both builds; checked scalar-cache tests **13/13** on Release;
  boundary tests **2/2** on both builds.

The C oracle confirms that later result expressions can mutate a named result's
shared data while its previously published length remains unchanged. Tests also
cover repeated locals in different result positions, named-result candidates
rejected by swapped returns, owned parameters copied into multiple results,
mixed scalar/fixed/grow/shrink results and interrupted result construction.
Astra reviewed the vector channels and named-result handling read-only.

Reports/logs use `build/mixed-results-*`. This slice keeps fixed/slice-to-owned
multi-result adaptation, anonymous owners, general control destinations and
whole-owner assignment behind explicit gates.
